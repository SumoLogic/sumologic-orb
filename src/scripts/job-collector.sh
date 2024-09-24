#!/bin/bash
VCS_SHORT=$(echo "$CIRCLE_BUILD_URL" | cut -d"/" -f4)
case "$VCS_SHORT" in
    gh)
    # For GitHub OAuth App integration type
    VCS=github
    ;;
    bb)
    # For GitHub OAuth App integration type
    VCS=bitbucket
    ;;
    circleci)
    # For GitHub App and Gitlab  integration type
    VCS=circleci
    ;;
    *)
    echo "No VCS found. Error" && exit 1
    ;;
esac
JOB_DATA_RAW=$(curl -s "https://circleci.com/api/v1.1/project/$VCS/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/$CIRCLE_BUILD_NUM?circle-token=${CIRCLE_TOKEN}")

if [[ "$JOB_DATA_RAW" =~ "Invalid token" ]];
then
    echo "Your circle-token parameter may be wrong Error: $JOB_DATA_RAW"
    exit 1
fi

if [[ -z "${JOB_DATA_RAW#"${JOB_DATA_RAW%%[! ]*}"}" ]];
then
    echo "No Job Found for $VCS/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/$CIRCLE_BUILD_NUM"
    exit 1
fi

# removing steps and circle_yml keys from object
JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq 'del(.circle_yml)' | jq 'del(.steps)')
JOB_NAME=$(echo "$JOB_DATA_RAW" | jq .workflows | jq .job_name)

if [ $? -ne 0 ] ; then
   echo "Error in parsing payload: $VCS/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/$CIRCLE_BUILD_NUM error: $JOB_DATA_RAW"
   exit 1
fi

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
if [ -n "$JOB_CUSTOM_DATA" ]
then
    echo "Appending custom data to the job data"
    JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq -c ". +  {\"custom_data\": $JOB_CUSTOM_DATA}")
else
    echo "No valid custom data found to append to the job data"
fi
echo "$JOB_DATA_RAW" > /tmp/sumologic-logs/job-collector.json
curl -s -w "SumoHTTPSendStatus: %{http_code}\n" -X POST -T /tmp/sumologic-logs/job-collector.json "${JOB_HTTP_SOURCE}"
echo "Job details sent to Sumo."
