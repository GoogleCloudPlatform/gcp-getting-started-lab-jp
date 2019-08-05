#!/usr/bin/python
#
# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from __future__ import print_function

import argparse
import os
import sys
import shutil
import time
import multiprocessing

import tensorflow as tf
import tensorflow.contrib.tensorrt as trt
import numpy as np

tf.logging.set_verbosity(tf.logging.INFO)

IMAGE_SIZE = 224
CROP_PADDING = 32

def get_calibration_files(data_dir, filename_pattern):
  """We verify that the correct Imagenet data folder has been mounted
  and validation data files of the form validation-00xxx-of-00128 are
  available.
  """
  if data_dir is None:
    return []
  files = tf.gfile.Glob(os.path.join(data_dir, filename_pattern))
  if files == []:
    raise ValueError('Can not find any files in {} with '
                     'pattern "{}"'.format(data_dir, filename_pattern))
  return files

def deserialize_image_record(record):
  keys_to_features = {
    'image/encoded': tf.FixedLenFeature((), tf.string, ''),
    'image/class/label': tf.FixedLenFeature([], tf.int64, -1),
  }

  with tf.name_scope('deserialize_image_record'):
    parsed = tf.parse_single_example(record, keys_to_features)
    image_bytes = tf.reshape(parsed['image/encoded'], shape=[])
    label = tf.cast(tf.reshape(parsed['image/class/label'], shape=[]),
                    dtype=tf.int32)
        
    # 'image/class/label' is encoded as an integer from 1 to
    # num_label_classes in order to generate the correct one-hot label
    # vector from this number, we subtract the number by 1 to make it
    # in [0, num_label_classes).
    label -= 1
    return image_bytes, label
      
def preprocess(record):
  image_bytes, label = deserialize_image_record(record)
  
  shape = tf.image.extract_jpeg_shape(image_bytes)
  image_height = shape[0]
  image_width = shape[1]
    
  padded_center_crop_size = tf.cast(
      ((IMAGE_SIZE / (IMAGE_SIZE + CROP_PADDING)) *
       tf.cast(tf.minimum(image_height, image_width), tf.float32)),
      tf.int32)

  offset_height = ((image_height - padded_center_crop_size) + 1) // 2
  offset_width = ((image_width - padded_center_crop_size) + 1) // 2
  crop_window = tf.stack([offset_height, offset_width,
                          padded_center_crop_size, padded_center_crop_size])
  image = tf.image.decode_and_crop_jpeg(image_bytes, crop_window, channels=3)
  image = tf.image.resize_bicubic([image], [IMAGE_SIZE, IMAGE_SIZE])[0]
  image = tf.reshape(image, [IMAGE_SIZE, IMAGE_SIZE, 3])
  image = tf.image.convert_image_dtype(image, tf.float32)
    
  return image, label
    
def convert_fp32_or_fp16(
    input_model_dir, output_model_dir, batch_size, precision_mode):
  """Optimize and quantize a input model with FP32 or FP16.
  """
  trt.create_inference_graph(
      input_graph_def=None,
      outputs=None,
      max_batch_size=batch_size,
      input_saved_model_dir=input_model_dir,
      output_saved_model_dir=output_model_dir,
      precision_mode=precision_mode)
  
def convert_int8(
    input_model_dir, output_model_dir, batch_size, precision_mode,
    calib_image_dir, input_tensor, output_tensor, epochs):
  
  # (TODO) Need to check if we need Tesla T4 when conversion.
  config = tf.ConfigProto()
  config.gpu_options.allow_growth = True
  
  # Get path to calibration data.
  calibration_files = get_calibration_files(calib_image_dir, 'validation*')
  
  # Create dataset and apply preprocess
  # (TODO) Get num cpus to set appropriate number to num_parallel_calls
  dataset = tf.data.TFRecordDataset(calibration_files)
  dataset = dataset.apply(
      tf.contrib.data.map_and_batch(
          map_func=preprocess, batch_size=batch_size,
          num_parallel_calls=multiprocessing.cpu_count()))
  
  """
  Step 1: Creating the calibration graph.
  """
  
  # Create TF-TRT INT8 calibration graph.
  trt_int8_calib_graph = trt.create_inference_graph(
      input_graph_def=None,
      outputs=[output_tensor],
      max_batch_size=batch_size,
      input_saved_model_dir=input_model_dir,    
      precision_mode=precision_mode)

  # Calibrate graph.
  with tf.Session(graph=tf.Graph(), config=config) as sess:
    tf.logging.info('preparing calibration data...')
    iterator = dataset.make_one_shot_iterator()
    next_element = iterator.get_next()
    
    tf.logging.info('Loading INT8 calibration graph...')
    output_node = tf.import_graph_def(
        trt_int8_calib_graph, return_elements=[output_tensor], name='')
    
    tf.logging.info('Calibrate model with calibration data...')
    for _ in range(epochs):
      sess.run(output_node,
               feed_dict={input_tensor: sess.run(next_element)[0]})
  
  """
  Step 2: Converting the calibration graph to inference graph
  """
  tf.logging.info('Creating TF-TRT INT8 inference engine...')
  trt_int8_calibrated_graph = trt.calib_graph_to_infer_graph(
      trt_int8_calib_graph)
  
  # Copy MetaGraph from base model.
  with tf.Session(graph=tf.Graph(), config=config) as sess:
    base_model = tf.saved_model.loader.load(
        sess, [tf.saved_model.tag_constants.SERVING], input_model_dir)
    
    metagraph = tf.MetaGraphDef()
    metagraph.graph_def.CopyFrom(trt_int8_calibrated_graph)
    for key in base_model.collection_def:
      if key not in ['variables', 'local_variables', 'model_variables',
                     'trainable_variables', 'train_op', 'table_initializer']:
        metagraph.collection_def[key].CopyFrom(base_model.collection_def[key])
        
    metagraph.meta_info_def.CopyFrom(base_model.meta_info_def)
    for key in base_model.signature_def:
      metagraph.signature_def[key].CopyFrom(base_model.signature_def[key])
      
  saved_model_builder = (
      tf.saved_model.builder.SavedModelBuilder(output_model_dir))

  # Write SavedModel with INT8 precision.
  with tf.Graph().as_default():
    tf.graph_util.import_graph_def(
        trt_int8_calibrated_graph, return_elements=[output_tensor], name='')
    with tf.Session(config=config) as sess:
      saved_model_builder.add_meta_graph_and_variables(
          sess, ('serve',), signature_def_map=metagraph.signature_def)

  # Ignore other meta graphs from the input SavedModel.
  saved_model_builder.save()

def main():
  parser = argparse.ArgumentParser(description='A TensorRT example')
  
  parser.add_argument(
    '--input-model-dir',
    default='models/resnet/original/00001',
    help='input directory of original model'    
  )
  parser.add_argument(
    '--output-dir',
    default='models/resnet/',
    help='output directory for converted models'
  )
  parser.add_argument(
    '--input-tensor',
    default='input_tensor:0',
    help='a name of TF input ops used in specified SavedModel file'
  )
  parser.add_argument(
    '--output-tensor',
    default='softmax_tensor:0',
    help='a name of TF output ops used in specified SavedModel file'
  )
  parser.add_argument(
    '--precision-mode',
    default='FP32',
    help='target precision for TF-TRT conversion (default: FP32)'
  )
  parser.add_argument(
    '--calib-image-dir',
    default='gs://path-to-imagenet-dataset',
    help='path to image dataset used for calibration for an INT8 model.')
  parser.add_argument(
    '--batch-size',
    type=int,
    default=64,
    help='batch size for output model.')
  parser.add_argument(
    '--calibration-epochs',
    type=int,
    default=10,
    help='number of epochs for INT8 calibration')
  
  args = parser.parse_args()

  # This program only supports FP32, FP16 and INT8 as a precision-mode.
  if args.precision_mode not in ['FP32', 'FP16', 'INT8']:
      raise ValueError(
        '{} is not a valid precision-mode.'.format(precision_mode))

  output_model_dir = os.path.join(
      args.output_dir, args.precision_mode, '00001')
  
  if os.path.exists(output_model_dir):
    shutil.rmtree(output_model_dir)
  
  if args.precision_mode in ['FP32', 'FP16']:
    convert_fp32_or_fp16(
        input_model_dir=args.input_model_dir,
        output_model_dir=output_model_dir,
        batch_size=args.batch_size,
        precision_mode=args.precision_mode)
  else:
    convert_int8(
        input_model_dir=args.input_model_dir,
        output_model_dir=output_model_dir,
        batch_size=args.batch_size,
        precision_mode=args.precision_mode,
        calib_image_dir=args.calib_image_dir,
        input_tensor=args.input_tensor,
        output_tensor=args.output_tensor,
        epochs=args.calibration_epochs)
    
if __name__ == '__main__':
  main()