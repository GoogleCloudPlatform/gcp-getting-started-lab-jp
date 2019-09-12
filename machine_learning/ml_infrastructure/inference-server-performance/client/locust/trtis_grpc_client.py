# Copyright 2019 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import grpc
import inspect
import numpy
import os
import time

from locust import Locust
from locust import TaskSet
from locust import task
from locust import events
from locust import HttpLocust

import tensorrtserver.api.model_config_pb2 as model_config
from tensorrtserver.api import api_pb2
from tensorrtserver.api import grpc_service_pb2
from tensorrtserver.api import grpc_service_pb2_grpc

from PIL import Image

import grpc.experimental.gevent as grpc_gevent
grpc_gevent.init_gevent()

DATA_DIR = 'data'
DATA_SIZE = 3
MIN_WAIT_MSEC = 800
MAX_WAIT_MSEC = 1200
TIMEOUT_MSEC = 2000

image_id = numpy.random.randint(DATA_SIZE) + 1
image_file = '{}/{:0>5}.jpg'.format(DATA_DIR, image_id)
img = Image.open(image_file).convert('RGB').resize((224, 224), Image.BILINEAR)
img = numpy.array(img).astype(numpy.float32)

input_bytes = img.tobytes()
request = grpc_service_pb2.InferRequest()

request.model_name = os.environ['MODEL_NAME']
request.model_version = -1
request.meta_data.batch_size = 1

output_message = api_pb2.InferRequestHeader.Output()
output_message.name = 'probabilities'
output_message.cls.count = 1

request.meta_data.output.extend([output_message])
request.meta_data.input.add(name='input')
request.raw_input.extend([input_bytes])

def stopwatch(func):
    def wrapper(*args, **kwargs):
        previous_frame = inspect.currentframe().f_back
        _, _, name, _, _ = inspect.getframeinfo(previous_frame)

        start = time.time()
        result = None

        try:
            result = func(*args, **kwargs)
        except Exception as e:
            total = int((time.time() - start) * 1000)
            events.request_failure.fire(
                request_type="grpc", name=name, response_time=total,
                exception=e)
        else:
            total = int((time.time() - start) * 1000)
            events.request_success.fire(
                request_type="grpc", name=name, response_time=total,
                response_length=0)
        return result
    return wrapper

class ProtocolClient():
    def __init__(self, host):
        self.host = host
        self.stub = None
        self.channel = None

    def new_connection(self):
        server_address = "{}:8001".format(self.host)
        self.channel = grpc.insecure_channel(server_address)
        self.stub = grpc_service_pb2_grpc.GRPCServiceStub(
            self.channel)

    def close_connection(self):
        self.channel.close()

    @stopwatch
    def predict(self, request):
        result = self.stub.Infer(request, TIMEOUT_MSEC)
        return result

class ProtocolLocust(Locust):
    def __init__(self):
        super(ProtocolLocust, self).__init__()
        self.client = ProtocolClient(self.host)

class ProtocolTasks(TaskSet):
    @task
    def invocations(self):
        self.client.new_connection()
        self.client.predict(request)
        self.client.close_connection()

class ProtocolUser(ProtocolLocust):
    task_set = ProtocolTasks
    min_wait = MIN_WAIT_MSEC
    max_wait = MAX_WAIT_MSEC
