#!/bin/bash
# Send data to SumoLogic
curl -s -X POST -T "${PARAM_PATH}" "${PARAM_HTTPSOURCE}"
