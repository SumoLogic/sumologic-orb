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

## Release
Orb in this repository is registered with a namespace in CircleCI already. When any PR is created or any release is created, a job is triggered in CircleCI. To make this job pass successfully you need to follow these steps: 

1. Create an account in [CircleCI](https://app.circleci.com) using your Sumologic GitHub account.
2. Authorize the account to add the SumoLogic organization.
3. Generate a CircleCI API token by following the steps [here](https://circleci.com/docs/guides/toolkit/managing-api-tokens/#creating-a-personal-api-token).
4. [Create a context](https://circleci.com/docs/guides/security/contexts/#create-and-use-a-context) and name it `orb-publishing` and set the `CIRCLE_TOKEN` as an environment variable within this context.

Any job triggered on PR and release creation in CircleCI will run a job orb-tools/publish in CircleCI. This job is responsible for publishing your orb in CircleCI repo, which can be referred by anyone in their CircleCI pipeline. For this job to pass you need to be the owner of the SumoLogic github organization. IT team can be requested for a temporary ownership access. Reference [ticket](https://sumologic.atlassian.net/servicedesk/customer/portal/5/HELP-35375).

The job created by PR creation results in the creation of a temporary dev orb (can be used to provide patch build) and Circle the job created by releaseCI results in an official orb release. Both of such orbs are accessible via a link which can be fetched from orb-tools/publish logs under "Publishing Orb Release" section.