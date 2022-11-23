#!/bin/bash
###############
# Begin Collecting
###############
DATA_URL="https://circleci.com/api/v2/workflow/$CIRCLE_WORKFLOW_ID/job?circle-token=${CIRCLE_TOKEN}"
WF_DATA=$(curl -s "$DATA_URL")
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
WF_ITEMS=$(echo "$WF_DATA" | jq '.items')
# GET URL PATH DATA
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
########################################
# Send end-of-workflow data to Sumologic
########################################
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

echo "SENDING FINAL WORKFLOW DATA"
echo "$WF_SL_PAYLOAD"
# echo "$WF_SL_PAYLOAD" > /tmp/sumologic-logs/workflow-collector.json
# curl -s -X POST -T /tmp/sumologic-logs/workflow-collector.json "${WORKFLOW_HTTP_SOURCE}"
curl -i \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
-X POST --data "$WF_SL_PAYLOAD" "${WORKFLOW_HTTP_SOURCE}"
echo "Complete. You may now find your worflow log in Sumologic."

# Looping through each job data
i="0"
while [ $i -lt "$WF_LENGTH" ]
do
    echo "looping: $i"
    # fetch the job info
    JOB_DATA=$(echo "$WF_ITEMS" | jq --arg i "$i" ".[$i]")
    JOB_NUMBER=$(echo "$JOB_DATA" | jq ".job_number")
    JOB_NAME=$(echo "$JOB_DATA" | jq ".name")
    #####
    # Send Job Data to SumoLogic
    #####
    if [ "$JOB_NUMBER" = "$CIRCLE_BUILD_NUM" ];
    then
        echo "This is the reporter job. Skipping"
    else
        echo "JOB: $JOB_NAME"
        echo "JOB NUM: $JOB_NUMBER"
        mkdir -p /tmp/sumologic-logs/
        if [ "$JOB_NUMBER" = "null" ];
        then
            echo "Approval Job, skipping"
        else
            JOB_DATA_RAW=$(curl -s "https://circleci.com/api/v1.1/project/$VCS/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/$JOB_NUMBER?circle-token=${CIRCLE_TOKEN}")
            WF_STEP_NAMES=$(echo "$JOB_DATA_RAW" | jq '.steps' | jq .[] | jq '.name')
            JOB_COLLECTOR_NAME="Job Collector"
            # Skip sending job data if it has already included job-collector command in one of it's steps
            if grep -q "$JOB_COLLECTOR_NAME"<<< "$WF_STEP_NAMES";
            then
                echo "This job log has already been sent to Sumo, skipping."
            else
                # Manually set job name as it is currently null
                JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq --arg JOBNAME "$JOB_NAME" '.job_name = $JOBNAME')
                # removing steps and circle_yml keys from object
                JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq 'del(.circle_yml)' | jq 'del(.steps)')
                echo "$JOB_DATA_RAW" > /tmp/sumologic-logs/job-collector.json
                curl -s -X POST -T /tmp/sumologic-logs/job-collector.json "${JOB_HTTP_SOURCE}"
            fi
        fi
    fi
    echo "rerunning loop"
    i="$((i+1))"
    echo "increment loop to $i"
    echo " ---------- "
    echo
done
echo "Complete. You may now find your job logs in Sumologic."