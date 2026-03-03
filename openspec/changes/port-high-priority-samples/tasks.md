# Tasks: Port High Priority Samples

## Completed

- [x] Create lambda-function-urls/python sample
  - [x] Create directory structure
  - [x] Write src/handler.py
  - [x] Write scripts/deploy.sh
  - [x] Write scripts/test.sh (7 test cases)
  - [x] Write README.md
  - [x] Add Terraform deployment option
  - [x] Test locally - all tests pass

- [x] Create stepfunctions-lambda/python sample
  - [x] Create directory structure
  - [x] Write src/lambda_adam.py, lambda_cole.py, lambda_combine.py
  - [x] Write src/state-machine.json
  - [x] Write scripts/deploy.sh
  - [x] Write scripts/test.sh (10 test cases)
  - [x] Write README.md
  - [x] Test locally - all tests pass

- [x] Update run-samples.sh with new samples
- [x] Update PORTING.md

- [x] Fix Lambda state timing issues in existing samples
  - [x] Add wait loop to lambda-cloudfront/python/scripts/deploy.sh
  - [x] Add wait loop to lambda-s3-http/python/scripts/deploy.sh
  - [x] Add wait loop to web-app-dynamodb/python/scripts/deploy.sh
  - [x] Add wait loop to web-app-rds/python/scripts/deploy.sh
  - [x] All 4 samples pass CI tests

## In Progress

- [ ] Fix lambda-layers/python sample
  - [x] Create directory structure
  - [x] Write src/layer/utils.py
  - [x] Write src/handler.py
  - [x] Write scripts/deploy.sh
  - [x] Write scripts/test.sh
  - [ ] Debug layer loading issue (/opt/python not in path)

## Blocked

- [ ] Create apigw-websockets/python sample
  - Blocked: API Gateway V2 not available in current LocalStack license
  - Action: Skip or document as requiring specific license

## To Do

- [ ] Create apigw-custom-domain sample
  - [ ] Research old implementation
  - [ ] Create directory structure
  - [ ] Write deployment and test scripts
  - [ ] Test locally

- [ ] Create ecs-ecr-app sample
  - [ ] Research old implementation
  - [ ] Create CloudFormation templates
  - [ ] Write deployment and test scripts
  - [ ] Test locally

- [ ] Push changes and verify CI
  - [ ] Commit all new samples
  - [ ] Push to master
  - [ ] Verify GitHub Actions runs tests
  - [ ] Fix any CI failures

## Notes

- lambda-function-urls: Working, 7 tests pass
- stepfunctions-lambda: Working, 10 tests pass
- lambda-layers: Issue with LocalStack not putting layer in Python path
- apigw-websockets: Requires API Gateway V2 (may not be in license)
