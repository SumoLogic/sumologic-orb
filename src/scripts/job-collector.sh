#!/bin/bash
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
JOB_DATA_RAW=$(curl -s "https://circleci.com/api/v1.1/project/$VCS/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/$CIRCLE_BUILD_NUM?circle-token=${PARAM_CIRCLETOKEN}")
# removing steps and circle_yml keys from object
JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq 'del(.circle_yml)' | jq 'del(.steps)')
JOB_NAME=$(echo "$JOB_DATA_RAW" | jq .workflows | jq .job_name)
JOB_STATUS=$(echo "$JOB_DATA_RAW" | jq .status)
echo "JOB: $JOB_NAME"
echo "JOB NUM: $CIRCLE_BUILD_NUM"
echo "STATUS: $JOB_STATUS"
#####
# Send Job Data to SumoLogic
#####
mkdir -p /tmp/sumologic-logs/
# manually set job name as it is currently null
JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq --arg JOBNAME "$JOB_NAME" '.job_name = $JOBNAME')
JOB_CUSTOM_DATA=$( jq -n \
                    --arg en "${PARAM_ENV}" \
                    --arg tm "${PARAM_TEAM}" \
                    --arg sv "${PARAM_SERVICE}" \
                    '{environment: $en, team: $tm, service: $sv}' )
# Append any custom data to the job data
echo "$JOB_CUSTOM_DATA"
if [ -n "$JOB_CUSTOM_DATA" ]
then
    echo "Appending custom data to the job data"
    JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq -c ". +  {\"custom_data\": $JOB_CUSTOM_DATA}")
else
    echo "No valid custom data found to append to the job data"
fi
echo "$JOB_DATA_RAW"
echo "$JOB_DATA_RAW" > /tmp/sumologic-logs/job-collector.json
curl -s -X POST -T /tmp/sumologic-logs/job-collector.json "${PARAM_JOBCOLLECTOR}"
echo "Job details sent to Sumo."