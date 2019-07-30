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

import os
import pickle
import time

import numpy as np

from config import EXPERIMENT_NAME
from common import EXPERIMENT_DIR
from locust import events

_success_data_saver = []
_failure_data_saver = []

def set_up_custom_handler(platform_name):
  """Set up custom handler.

  Args:
    platform_name: A string, e.g. "trtis"
  """

  def custom_success_handler(request_type, name, response_time, response_length,
                             **kwargs):
    """Event handler that get triggered on every successful request."""
    _success_data_saver.append((time.time(), response_time))

  def custom_failure_handler(request_type, name, response_time, exception,
                             **kwargs):
    """Event handler that get triggered on every failed request."""
    _failure_data_saver.append((time.time(), str(exception)))

  def custom_quit_handler(**kwargs):
    """Event handler that get triggered on exit."""
    cur_pid = os.getpid()

    # save latency and error data to pickle files
    pickle.dump(
        _success_data_saver,
        open(
            os.path.join(EXPERIMENT_DIR, EXPERIMENT_NAME,
                         "%s_success_data_%d.p" % (platform_name, cur_pid)),
            "wb"))

    pickle.dump(
        _failure_data_saver,
        open(
            os.path.join(EXPERIMENT_DIR, EXPERIMENT_NAME,
                         "%s_failure_data_%d.p" % (platform_name, cur_pid)),
            "wb"))

    # print out percentiles
    if _success_data_saver:
      resp_stat = np.percentile(_success_data_saver,
                                [1, 2, 5, 10, 90, 95, 98, 99])
      print("p1, p2, p5, p10, p90, p95, p98, p99")
      print(resp_stat)

  events.request_success += custom_success_handler
  events.request_failure += custom_failure_handler
  events.quitting += custom_quit_handler
