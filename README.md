# Sumologic Orb
Easily capture analytics from your CircleCI jobs in your Sumologic dashboard!

## Setup

To configure the orb follow the instructions in [Circle CI for build and deploy](https://help.sumologic.com/docs/observability/sdo/set-up-sdo/sdo-manual-configuration/#circleci-for-build-and-deploy) docs.

To know more about the parameters and example configuration refer [Sumologic Orb documentation](https://circleci.com/developer/en/orbs/orb/sumologic/sumologic).

## job-collector
Add this command to your job with environment, team or service custom-data values as parameters. This command will run with the rest of the commands of the job for sending job log. This command has been introduced so as to send environment, team and service information at job level. If this command is not included at job level in one of it's steps, then the workflow-collector job will send the job log. Using it without the parameters will result in empty custom-data values being sent to Sumo.

## workflow-collector
Add this job to your workflow with no require statements. This job will run in parallel with the rest of your workflow for monitoring the health of all jobs in the Workflow. It exits when all other jobs have completed. Custom data can be supplied via the custom-data parameter in the form of valid JSON. Keys and values can be supplied literally or as environment variables, though supplying values as additional, nested JSON is not supported. Use `timeout-seconds` parameter (defaults to 180s/3mins) to end the workflow-collector early when required.

## Testing

* [Install](https://circleci.com/docs/local-cli/#installation) and [configure](https://circleci.com/docs/local-cli/#configure-the-cli) the CircleCI CLI Tool.
* brew install yamllint shellcheck
* Run the [validation](https://circleci.com/docs/testing-orbs/#validation) commands

    `yamllint ./src`
    `circleci orb validate orb.yml`
    `shellcheck src/scripts/*.sh`
