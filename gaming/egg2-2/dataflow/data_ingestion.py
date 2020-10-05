# Copyright 2017 Google Inc.
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
"""`data_ingestion.py` is a Dataflow pipeline which reads a file and writes its
contents to a BigQuery table.
This example does not do any transformation on the data.


This Sample code from https://github.com/GoogleCloudPlatform/professional-services/blob/master/examples/dataflow-python-examples/dataflow_python_examples/data_ingestion.py for E.G.G hands on
"""

from __future__ import absolute_import
import argparse
import logging
import re
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions


class DataIngestion:
    """A helper class which contains the logic to translate the file into
    a format BigQuery will accept."""

    def parse_method(self, string_input):
        """This method translates a single line of comma separated values to a
        dictionary which can be loaded into BigQuery.

        Args:
            string_input: A comma separated list of values in the form of
                state_abbreviation,gender,year,name,count_of_babies,dataset_created_date
                Example string_input: KS,F,1923,Dorothy,654,11/28/2016

        Returns:
            A dict mapping BigQuery column names as keys to the corresponding value
            parsed from string_input. In this example, the data is not transformed, and
            remains in the same format as the CSV.
            example output:
            {
                'state': 'KS',
                'gender': 'F',
                'year': '1923',
                'name': 'Dorothy',
                'number': '654',
                'created_date': '11/28/2016'
            }
         """
        # Strip out carriage return, newline and quote characters.
        values = re.split(",",
                          re.sub('\r\n', '', re.sub(u'"', '', string_input)))
        row = dict(
            zip(('state', 'gender', 'year', 'name', 'number', 'created_date'),
                values))
        return row


def run(argv=None):
    """The main function which creates the pipeline and runs it."""

    parser = argparse.ArgumentParser()

    # Here we add some specific command line arguments we expect.
    # Specifically we have the input file to read and the output table to write.
    # This is the final stage of the pipeline, where we define the destination
    # of the data. In this case we are writing to BigQuery.
    parser.add_argument(
        '--input',
        dest='input',
        required=False,
        help='Input file to read. This can be a local file or '
        'a file in a Google Storage Bucket.',
        # This example file contains a total of only 10 lines.
        # Useful for developing on a small set of data.
        default='gs://python-dataflow-example/data_files/head_usa_names.csv')

    # This defaults to the lake dataset in your BigQuery project. You'll have
    # to create the lake dataset yourself using this command:
    # bq mk lake
    parser.add_argument('--output',
                        dest='output',
                        required=False,
                        help='Output BQ table to write results to.',
                        default='lake_egg2.usa_names')

    # コマンドライン引数のパース
    known_args, pipeline_args = parser.parse_known_args(argv)

    # DataIngestion is a class we built in this script to hold the logic for
    # transforming the file into a BigQuery table.
    data_ingestion = DataIngestion()

    # Initiate the pipeline using the pipeline arguments passed in from the
    # command line. This includes information such as the project ID and
    # where Dataflow should store temp files.
    p = beam.Pipeline(options=PipelineOptions(pipeline_args))

    (p
        # ファイルの読み込み。行の最初からスタートするので、ヘッダー行をスキップしています。
     | 'Read from a File' >> beam.io.ReadFromText(known_args.input,
                                                  skip_header_lines=1)
     # パイプラインのこの段階では、文字列として入力されたCSVファイルの単一行から、
     # BigQueryで使用可能な辞書オブジェクトに変換されます。
     # この関数は、パイプラインの前のステージからの入力を使用して、ワーカーで並行して実行されます。
     | 'String To BigQuery Row' >>
     beam.Map(lambda s: data_ingestion.parse_method(s))
     | 'Write to BigQuery' >> beam.io.Write(
         beam.io.WriteToBigQuery(
             # テーブル名は必須パラメータ. 実行時に指定していない場合は、`lake_egg2.usa_names` を利用
             known_args.output,
             # アウトプット先のテーブルスキーマ
             schema='state:STRING,gender:STRING,year:STRING,name:STRING,'
             'number:STRING,created_date:STRING',
             # テーブルがまだ存在しない場合は作成します。
             create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
             # 書き込む前にBigQueryテーブルのすべてのデータを削除。
             write_disposition=beam.io.BigQueryDisposition.WRITE_TRUNCATE)))
    p.run().wait_until_finish()


if __name__ == '__main__':
    logging.getLogger().setLevel(logging.INFO)
    run()
