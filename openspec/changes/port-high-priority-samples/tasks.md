# Tasks: Port High Priority Samples

Source: https://github.com/localstack-samples/localstack-pro-samples

## Completed

### Ported from Original Repo

- [x] Port `lambda-function-urls-python` → `samples/lambda-function-urls/python`
  - [x] Create directory structure
  - [x] Port handler.py
  - [x] Write scripts/deploy.sh
  - [x] Write scripts/test.sh (7 test cases)
  - [x] Add Terraform deployment option
  - [x] CI passing

- [x] Port `stepfunctions-lambda` → `samples/stepfunctions-lambda/python`
  - [x] Create directory structure
  - [x] Port Lambda functions (adam, cole, combine)
  - [x] Port state-machine.json
  - [x] Write scripts/deploy.sh
  - [x] Write scripts/test.sh (10 test cases)
  - [x] CI passing

### New Samples (Not Ports)

- [x] Create `lambda-cloudfront/python` (new sample)
- [x] Create `lambda-s3-http/python` (new sample)
- [x] Create `web-app-dynamodb/python` (new sample)
- [x] Create `web-app-rds/python` (new sample)

### Infrastructure

- [x] Fix Lambda state timing issues in all deploy scripts
- [x] Fix CI workflow to run all tests on push to master
- [x] All 6 samples pass CI

## In Progress

- [ ] Port `serverless-lambda-layers` → `samples/lambda-layers/javascript`
  - [x] Research original implementation
  - [x] Create directory structure with serverless.yml
  - [x] Port handler.js and layer/nodejs/lib.js
  - [x] Write scripts/deploy.sh
  - [x] Write scripts/test.sh (5 test cases)
  - [x] Add to run-samples.sh
  - [ ] Test locally and fix any issues
  - [ ] Verify CI passes

## To Do

### Port from Original Repo

- [ ] Port `serverless-websockets` → `samples/apigw-websockets/javascript`
  - Uses Serverless Framework
  - May require API Gateway V2 (check LocalStack license)

- [ ] Port `ecs-ecr-container-app` → `samples/ecs-ecr-app/python`
  - [ ] Research original implementation
  - [ ] Create directory structure
  - [ ] Write deployment and test scripts

- [ ] Port `apigw-custom-domain` → `samples/apigw-custom-domain/python`
  - [ ] Research original implementation
  - [ ] Create directory structure
  - [ ] Write deployment and test scripts

## Cleanup

- [x] Remove broken `samples/lambda-layers/python` (replaced with javascript version)

## CI Status

Latest: https://github.com/dmacvicar/localstack-aws-samples/actions/runs/22632353146
6 samples passing (lambda-layers/javascript pending test).
