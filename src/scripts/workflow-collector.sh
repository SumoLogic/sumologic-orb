#!/bin/bash
WF_DATA=$(curl -s "https://circleci.com/api/v2/workflow/$CIRCLE_WORKFLOW_ID/job?circle-token=${CIRCLE_TOKEN}")
WF_ITEMS=$(echo "$WF_DATA" | jq '.items')
WF_LENGTH=$(echo "$WF_ITEMS" | jq length)
WF_MESSAGE=$(echo "$WF_DATA" | jq '.message')

# Exit if no Workflow.
if [ "$WF_MESSAGE" = "\"Workflow not found\"" ];
then
    echo "No Workflow was found."
    echo "Your circle-token parameter may be wrong or you do not have access to this Workflow."
    exit 1
fi

VCS_SHORT=$(echo "$CIRCLE_BUILD_URL" | cut -d"/" -f4)
case "$VCS_SHORT" in
    gh)
    VCS=github
    ;;
    bb)
    VCS=bitbucket
    ;;
    *)
    echo "No VCS found. Error" && exit 1
    ;;
esac

# Get the current state of all jobs.
WF_SL_PAYLOAD=$(curl -s "https://circleci.com/api/v2/workflow/$CIRCLE_WORKFLOW_ID?circle-token=${CIRCLE_TOKEN}" | jq '.')

# Append any custom data to the workflow data
ESCAPED_JSON=$(echo "${PARAM_CUSTOMDATA}" | sed -E 's/([^\]|^)"/\1\\"/g')
CUSTOM_DATA=$(eval "echo $ESCAPED_JSON")
if [[ -n "${PARAM_CUSTOMDATA}" ]] && echo "$CUSTOM_DATA" | jq -e;
then
    echo "Appending custom data to the workflow data"
    WF_SL_PAYLOAD=$(echo "$WF_SL_PAYLOAD" | jq -c ". +  {\"custom_data\": $CUSTOM_DATA} + {\"items\": $WF_ITEMS}")
else
    echo "No valid custom data found to append to the workflow data"
fi

echo "Sending current Workflow state to Sumo"
curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data "$WF_SL_PAYLOAD" "${WORKFLOW_HTTP_SOURCE}"

declare -A job_status_array
# Set FIRST_RUN to true to ensure all initial updates are sent.
FIRST_RUN=true
# While we still have jobs which are runnung.
TIMEOUT=$(date -d "${PARAM_TIMEOUT_SECONDS} seconds")
while true
do
  NOW=date
  if [[ $(date) > $TIMEOUT ]];
  then
    echo "Monitoring loop exceeded timeout of $PARAM_TIMEOUT_SECONDS seconds. Breaking loop and ending the job."
    break
  fi

  WF_DATA=$(curl -s "https://circleci.com/api/v2/workflow/$CIRCLE_WORKFLOW_ID/job?circle-token=${CIRCLE_TOKEN}")
  WF_ITEMS=$(echo "$WF_DATA" | jq '.items')
  WF_LENGTH=$(echo "$WF_ITEMS" | jq length)

  WF_SL_PAYLOAD=$(curl -s "https://circleci.com/api/v2/workflow/$CIRCLE_WORKFLOW_ID?circle-token=${CIRCLE_TOKEN}" | jq '.')
  WF_STATUS=$(echo "$WF_SL_PAYLOAD" | jq -r ".status")

  if [[ "$WF_STATUS" != "running" ]];
  then
    echo "Workflow status no longer running. Now: ${WF_STATUS}. Breaking loop."
    break
  fi

  # Check all jobs.
  i="0"
  while [ $i -lt "$WF_LENGTH" ]
  do
    JOB_DATA=$(echo "$WF_ITEMS" | jq --arg i "$i" ".[$i]")
    JOB_NUMBER=$(echo "$JOB_DATA" | jq -r ".job_number")
    JOB_STATUS=$(echo "$JOB_DATA" | jq -r '.status')
    JOB_NAME=$(echo "$JOB_DATA" | jq -r ".name")
    if [[ "${JOB_NAME}" != "workflow-collector" ]];
    then
      if ! [ "${job_status_array["${JOB_NAME}"]}" ];
      then
        echo "Job '$JOB_NAME' (job number: '$JOB_NUMBER') not tracked, adding to array with status of '$JOB_STATUS'."
        job_status_array["${JOB_NAME}"]=$JOB_STATUS
      fi

      if [[ "$JOB_NUMBER" == "null" ]] && [[ "$JOB_STATUS" != "blocked" ]];
      then
        echo "'$JOB_NAME' has a job number of 'null' and status of '$JOB_STATUS'. What's gone wrong?"
      elif [[ "$JOB_NUMBER" != "null" ]];
      then
        JOB_DATA_RAW=$(curl -s "https://circleci.com/api/v1.1/project/$VCS/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/$JOB_NUMBER?circle-token=${CIRCLE_TOKEN}")
        JOB_STATUS=$(echo "$JOB_DATA_RAW" | jq -r '.status')
        # Manually set job name as it is currently null
        JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq --arg JOBNAME "$JOB_NAME" '.job_name = $JOBNAME')
        JOB_STEP_NAMES=$(echo "$JOB_DATA_RAW" | jq '.steps' | jq .[] | jq '.name')
        # Remove steps and circle_yml keys from object
        JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq 'del(.circle_yml)' | jq 'del(.steps)')
        JOB_COLLECTOR_NAME="Job Collector"
        # Check if already monitored by a Job Collector.
        if [[ ${JOB_STEP_NAMES[@]} =~ $JOB_COLLECTOR_NAME ]]
        then
          echo "This job is being monitored by a Job Collector - skipping sending an update to SumoLogic."
        else
          # Handle changes in state.
          if [[ "${job_status_array["${JOB_NAME}"]}" != "$JOB_STATUS" ]] || $FIRST_RUN; then
            # Send update in status to SumoLogic
            echo "Job '$JOB_NAME' status has changed '${job_status_array["${JOB_NAME}"]}' -> '$JOB_STATUS'. Sending update to SumoLogic."
            JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq -c '.')
            if [[ -n "${PARAM_CUSTOMDATA}" ]] && echo "$CUSTOM_DATA" | jq -e;
            then
                JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq -c ". +  {\"custom_data\": $CUSTOM_DATA}")
            else
                echo "No valid custom data found to append to the job data."
            fi
            curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data "$JOB_DATA_RAW" "${JOB_HTTP_SOURCE}"
          fi
          job_status_array["${JOB_NAME}"]="$JOB_STATUS"
        fi
      fi
    fi
    i="$((i+1))"
    # echo "Incremented loop to $i. Continuing..."
  done
  # Set first run to false, only required for initial updates to be sent.
  FIRST_RUN=false
  # Quick loop over the job_status_array to see if we're all done
  FINISHED=true
  for k in "${!job_status_array[@]}"
  do
    if [[ "${job_status_array[$k]}" == "blocked" ]]; then
        FINISHED=false
        break
    fi
    if [[ "${job_status_array[$k]}" == "queued" ]]; then
        FINISHED=false
        break
    fi
    if [[ "${job_status_array[$k]}" == "running" ]]; then
      if [[ "$k" != "workflow-collector" ]]; then
        FINISHED=false
        break
      fi
    fi
  done

  if $FINISHED; then
    echo "All jobs are in non running state other than the workflow-collector."

    # Get the final state of all jobs.
    WF_SL_PAYLOAD=$(curl -s "https://circleci.com/api/v2/workflow/$CIRCLE_WORKFLOW_ID?circle-token=${CIRCLE_TOKEN}" | jq '.')

    # Append any custom data to the workflow data
    ESCAPED_JSON=$(echo "${PARAM_CUSTOMDATA}" | sed -E 's/([^\]|^)"/\1\\"/g')
    CUSTOM_DATA=$(eval "echo $ESCAPED_JSON")
    if [[ -n "${PARAM_CUSTOMDATA}" ]] && echo "$CUSTOM_DATA" | jq -e;
    then
        echo "Appending custom data to the workflow data"
        WF_SL_PAYLOAD=$(echo "$WF_SL_PAYLOAD" | jq -c ". +  {\"custom_data\": $CUSTOM_DATA} + {\"items\": $WF_ITEMS}")
    else
        echo "No valid custom data found to append to the workflow data."
    fi

    CURRENT_WF_STATUS=$(echo "$WF_SL_PAYLOAD" | jq -cr ".status")
    CURRENT_WF_STOPPED_AT=$(echo "$WF_SL_PAYLOAD" | jq -cr ".stopped_at")
    echo "Workflow is finishing, adjusting state in final payload accordingly."
    if [[ "$CURRENT_WF_STATUS" == "failing" ]];
    then
      echo "Current workflow status is 'failing'. Setting status to 'failed' in final payload."
      WF_SL_PAYLOAD=$(echo "$WF_SL_PAYLOAD" | jq -c --arg STATUS "failed" '.status = $STATUS')
    elif [[ "$CURRENT_WF_STATUS" == "running" ]];
    then
      echo "Current workflow status is 'running'. Setting status to 'success' in final payload."
      echo "Warning! This assumes that all job states were successful otherwise the workflow status would be 'failing', 'error' or other."
      WF_SL_PAYLOAD=$(echo "$WF_SL_PAYLOAD" | jq -c --arg STATUS "success" '.status = $STATUS')
    fi

    if [[ "$CURRENT_WF_STOPPED_AT" == "null" ]]; then
      STOPPED_AT=$(date +%Y-%m-%dT%H:%M:%SZ)
      echo "Stopped at is null so setting it to '$STOPPED_AT'."
      WF_SL_PAYLOAD=$(echo "$WF_SL_PAYLOAD" | jq -c --arg STOPPED_AT "$STOPPED_AT" '.stopped_at = $STOPPED_AT')
    fi

    echo "Sending final Workflow state to Sumo"
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data "$WF_SL_PAYLOAD" -s "${WORKFLOW_HTTP_SOURCE}"
    echo "Finishing up."
    break
  else
    echo "Some jobs are still queued or in progress. Continuing..."
  fi
done