package main

import (
	json "encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/cloudwatchlogs"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	envAWSRegion   = "AWS_REGION"
	envCWLogGroup  = "CW_LOG_GROUP_NAME"
	envCWLogStream = "CW_LOG_STREAM_NAME"
)

type Request struct {
	Body       string `json:"body"`
	Attributes `json:"attributes"`
}

type Attributes struct {
	LogFileName string `json:"log.file.name"`
}

func main() {
	region := os.Getenv(envAWSRegion)
	if region == "" {
		exitErrorf("[TEST FAILURE] AWS Region required. Set the value for environment variable- %s", envAWSRegion)
	}

	logGroup := os.Getenv(envCWLogGroup)
	if logGroup == "" {
		exitErrorf("[TEST FAILURE] Log group name required. Set the value for environment variable- %s", envCWLogGroup)
	}

	logStream := os.Getenv(envCWLogStream)
	if logStream == "" {
		exitErrorf("[TEST FAILURE] Log stream name required. Set the value for environment variable- %s", envCWLogStream)
	}

	inputRecord := os.Args[1]
	if inputRecord == "" {
		exitErrorf("[TEST FAILURE] Total input record number required. Set the value as the first argument")
	}
	totalInputRecord, _ := strconv.Atoi(inputRecord)
	// Map for counting unique records in corresponding destination
	inputMap := make(map[string]bool)

	totalRecordFound := 0
	cwClient, err := getCWClient(region)
	if err != nil {
		exitErrorf("[TEST FAILURE] Unable to create new CloudWatch client: %v", err)
	}

	totalRecordFound, inputMap = validate_cloudwatch(cwClient, logGroup, logStream, inputMap)

	// Get benchmark results based on log loss, log delay and log duplication
	get_results(totalInputRecord, totalRecordFound, inputMap)
}

// Creates a new CloudWatch Client
func getCWClient(region string) (*cloudwatchlogs.CloudWatchLogs, error) {
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(region)},
	)

	if err != nil {
		return nil, err
	}

	return cloudwatchlogs.New(sess), nil
}

// Validate logs in CloudWatch.
// Similar logic as S3 validation.
func validate_cloudwatch(cwClient *cloudwatchlogs.CloudWatchLogs, logGroup string, logStream string, inputMap map[string]bool) (int, map[string]bool) {
	var forwardToken *string
	var input *cloudwatchlogs.GetLogEventsInput
	cwRecordCounter := 0

	// Returns all log events from a CloudWatch log group with the given log stream.
	// This approach utilizes NextForwardToken to pull all log events from the CloudWatch log group.
	for {
		if forwardToken == nil {
			input = &cloudwatchlogs.GetLogEventsInput{
				LogGroupName:  aws.String(logGroup),
				LogStreamName: aws.String(logStream),
				StartFromHead: aws.Bool(true),
			}
		} else {
			input = &cloudwatchlogs.GetLogEventsInput{
				LogGroupName:  aws.String(logGroup),
				LogStreamName: aws.String(logStream),
				NextToken:     forwardToken,
				StartFromHead: aws.Bool(true),
			}
		}

		/*
		 * In testing we have found that CW GetLogEvents results are highly inconsistent
		 * Re-running validation long after tests shows that fewer events were lost than
		 * first calculated. So we sleep between calls to ensure we never exceed 1 TPS
		 * load_test.py also has a sleep before validation runs.
		 */
		time.Sleep(1 * time.Second)

		response, err := cwClient.GetLogEvents(input)
		for err != nil {
			// retry for throttling exception
			if strings.Contains(err.Error(), "ThrottlingException: Rate exceeded") {
				time.Sleep(1 * time.Second)
				response, err = cwClient.GetLogEvents(input)
			} else {
				exitErrorf("[TEST FAILURE] Error occurred to get the log events from log group: %q., %v", logGroup, err)
			}
		}

		for _, event := range response.Events {
			log := aws.StringValue(event.Message)
			data := Request{}
			json.Unmarshal([]byte(log), &data)
			// Treat the last 8 characters as the recordID since that will most likely be unique
			// Format of the log messages: "<timestamp> <message>". The message is randomly generated, so
			// the last 8 characters can act as a unique identifier
			recordId := data.Body[len(data.Body)-8:]
			cwRecordCounter += 1
			if _, ok := inputMap[recordId]; !ok {
				// Setting true to indicate that this record was found in the destination
				inputMap[recordId] = true
			}
		}

		// Same NextForwardToken will be returned if we reach the end of the log stream
		if aws.StringValue(response.NextForwardToken) == aws.StringValue(forwardToken) {
			break
		}

		forwardToken = response.NextForwardToken
	}

	return cwRecordCounter, inputMap
}

type ValidatorResults struct {
	TotalInputRecord     int
	TotalRecordFound     int
	UniqueRecordFound    int
	DuplicateRecordFound int
	PercentLoss          int
	MissingRecordFound   int
}

func get_results(totalInputRecord int, totalRecordFound int, recordMap map[string]bool) {
	// Count how many unique records were found in the destination
	uniqueRecordFound := len(recordMap)
	results := &ValidatorResults{TotalInputRecord: totalInputRecord,
		TotalRecordFound:     totalRecordFound,
		UniqueRecordFound:    uniqueRecordFound,
		DuplicateRecordFound: totalRecordFound - uniqueRecordFound,
		PercentLoss:          (totalInputRecord - uniqueRecordFound) * 100 / totalInputRecord,
		MissingRecordFound:   totalInputRecord - uniqueRecordFound}
	jsonResults, err := json.Marshal(results)
	if err != nil {
		exitErrorf("Failure marshalling results to json: %s", err.Error())
	}
	fmt.Println(string(jsonResults))
}

func exitErrorf(msg string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, msg+"\n", args...)
	os.Exit(1)
}
