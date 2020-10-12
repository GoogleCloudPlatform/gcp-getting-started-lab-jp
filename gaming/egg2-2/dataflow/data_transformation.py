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

""" data_transformation.py is a Dataflow pipeline which reads a file and writes
its contents to a BigQuery table.

This example reads a json schema of the intended output into BigQuery,
and transforms the date data to match the format BigQuery expects.

This Sample code from https://github.com/GoogleCloudPlatform/professional-services/blob/master/examples/dataflow-python-examples/dataflow_python_examples/data_transformation.py for E.G.G hands on
"""

from __future__ import absolute_import
import argparse
import csv
import logging
import os

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.io.gcp.bigquery import parse_table_schema_from_json


class DataTransformation:
    def __init__(self):
        self.schema_str = '''
        {"fields": [
                {
                    "name": "state",
                    "type": "STRING",
                    "description": "Short abbreviation for state where the child was born.  For example 'NY' for New York."
                },
                {
                    "name": "gender",
                    "type": "STRING",
                    "description": "'F' for female and 'M' for Male."
                },
                {
                    "name": "year",
                    "type": "DATE",
                    "description": "Year the child was born in BigQuery date format."
                },
                {
                    "name": "name",
                    "type": "STRING",
                    "description": "The child's first name."
                },
                {
                    "name": "number",
                    "type": "INTEGER",
                    "description": "The number of new born children sharing this name for the year in the given state."
                },
                {
                    "name": "created_date",
                    "type": "STRING",
                    "description": "Date this data was created."
                }
            ]
        }'''

    def parse_method(self, string_input):
        schema = parse_table_schema_from_json(self.schema_str)
        field_map = [f for f in schema.fields]
        reader = csv.reader(string_input.split('\n'))
        for csv_row in reader:
            values = [x for x in csv_row]
            # Our source data only contains year, so default January 1st as the
            # month and day.
            month = u'01'
            day = u'01'
            # The year comes from our source data.
            year = values[2]

            row = {}
            i = 0
            for value in values:
                if field_map[i].type == 'DATE':
                    value = u'-'.join((year, month, day))
                row[field_map[i].name] = value
                i += 1
            return row


def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--input', dest='input', required=False,
        help='Input file to read.  This can be a local file or '
             'a file in a Google Storage Bucket.',
        default='gs://python-dataflow-example/data_files/head_usa_names.csv')
    parser.add_argument('--output', dest='output', required=False,
                        help='Output BQ table to write results to.',
                        default='lake_egg2.usa_names_transformed')

    known_args, pipeline_args = parser.parse_known_args(argv)
    data_ingestion = DataTransformation()

    p = beam.Pipeline(options=PipelineOptions(pipeline_args))
    schema = parse_table_schema_from_json(data_ingestion.schema_str)

    (p
    | 'Read From Text' >> beam.io.ReadFromText(known_args.input,
                                                skip_header_lines=1)
     | 'String to BigQuery Row' >> beam.Map(lambda s:
                                            data_ingestion.parse_method(s))
     | 'Write to BigQuery' >> beam.io.Write(
                beam.io.WriteToBigQuery(
                    known_args.output,
                    schema=schema,
                    create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
                    write_disposition=beam.io.BigQueryDisposition.WRITE_TRUNCATE)))
    p.run().wait_until_finish()


if __name__ == '__main__':
    logging.getLogger().setLevel(logging.INFO)
    run()
