/*
Copyright © 2022 Cameron Larsen <cameron.larsen@kuali.co>

*/
package cmd

import (
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/eks"
	"github.com/spf13/cobra"
)

// rootCmd represents the base command when called without any subcommands
var (
	// init flag vars
	region      string
	clusterName string
	quick       bool
	envExist    bool

	rootCmd = &cobra.Command{
		Use:   "clusterupdate",
		Short: "Update EKS Cluster AMI's",
		Long: `A CLI tool to be used with github actions to update 
EKS cluster AMI's. For example:
clusterupdate --quick --region us-east-1 --cluster-name my-cluster`,
		Args: cobra.MinimumNArgs(0),
		Run: func(cmd *cobra.Command, args []string) {
		}, // do things here
	}
)

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	// Here you will define your flags and configuration settings.
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVarP(&region, "region", "r", "us-east-1", "AWS region (required)")
	rootCmd.PersistentFlags().StringVarP(&clusterName, "cluster-name", "c", "", "EKS cluster name (required)")
	rootCmd.PersistentFlags().BoolVar(&quick, "quick", true, "Target empty nodegroups first for quick update")

	// mark some flags as required
	rootCmd.MarkFlagRequired("region")
	rootCmd.MarkFlagRequired("cluster-name")

}

func waitUntilActive(attempts int, sleep time.Duration, clusterName string, client *eks.EKS) bool {
	// set max backoff of 1m
	var maxTime = time.Duration(60000000000)
	active, state := isClusterActive(clusterName, client)
	log.Printf("  * %s state is: '%s'", clusterName, state)
	if active == true {
		return true
	}

	if attempts--; attempts > 0 {
		// Add some randomness to prevent creating a Thundering Herd
		jitter := time.Duration(rand.Int63n(int64(sleep)))
		sleep = sleep + jitter/2
		log.Printf("  * Checking again in %s", sleep)
		time.Sleep(sleep)
		sleep = sleep * 2
		if sleep > maxTime {
			sleep = maxTime
		}
		return waitUntilActive(attempts, sleep, clusterName, client)
	}

	return false
}

func waitUntilUpdateComplete(attempts int, sleep time.Duration, nodeGroup, clusterName string, client *eks.EKS) bool {
	// set max backoff of 1m
	var maxTime = time.Duration(60000000000)
	active, state := isUpdateComplete(nodeGroup, clusterName, client)
	if active == true {
		log.Printf("  * %s state: '%s' - resuming work.", nodeGroup, state)
		return true
	} else {
		log.Printf("  * %s state: '%s'", nodeGroup, state)
	}

	if attempts--; attempts > 0 {
		// Add some randomness to prevent creating a Thundering Herd
		jitter := time.Duration(rand.Int63n(int64(sleep)))
		sleep = sleep + jitter/2
		time.Sleep(sleep)
		sleep = sleep * 2
		if sleep > maxTime {
			sleep = maxTime
		}
		return waitUntilUpdateComplete(attempts, sleep, nodeGroup, clusterName, client)
	}

	return false
}

func isEnvExist(key string) bool {
	// verify if env var is set
	if _, ok := os.LookupEnv(key); ok {
		return true
	}
	return false
}

func isUpdateComplete(nodeGroup string, clusterName string, client *eks.EKS) (bool, string) {
	// checks update status for a specified nodegroup
	var (
		describeNodegroupOutput *eks.DescribeNodegroupOutput
		err                     error
	)
	describeNodegroupOutput, err = client.DescribeNodegroup(&eks.DescribeNodegroupInput{
		ClusterName:   &clusterName,
		NodegroupName: &nodeGroup,
	})
	if err != nil {
		log.Fatalf("%v", err)
	}

	if *describeNodegroupOutput.Nodegroup.Status == "ACTIVE" {
		return true, *describeNodegroupOutput.Nodegroup.Status
	}

	return false, *describeNodegroupOutput.Nodegroup.Status
}

func isClusterExist(clusterName string, client *eks.EKS) bool {
	// verify if cluster exists in specified region
	_, err := client.DescribeCluster(&eks.DescribeClusterInput{
		Name: &clusterName,
	})
	if err != nil {
		log.Fatalf("%v", err)
		return false
	}

	return true
}

func isClusterActive(clusterName string, client *eks.EKS) (bool, string) {
	// verify if cluster is ready
	var (
		clusterStatus         string
		describeClusterOutput *eks.DescribeClusterOutput
		err                   error
	)
	describeClusterOutput, err = client.DescribeCluster(&eks.DescribeClusterInput{
		Name: &clusterName,
	})
	if err != nil {
		log.Fatalf("%v", err)
		return false, "ERROR"
	}
	clusterStatus = aws.StringValue(describeClusterOutput.Cluster.Status)
	if clusterStatus == "ACTIVE" {
		return true, clusterStatus
	}
	return false, clusterStatus
}

func updateNodeGroup(nodeGroup, clusterName string, client *eks.EKS) bool {
	// updates a specified nodegroup
	_, err := client.UpdateNodegroupVersion(&eks.UpdateNodegroupVersionInput{
		ClusterName:   &clusterName,
		NodegroupName: &nodeGroup,
	})
	if err != nil {
		log.Fatalf("%v", err)
		return false
	}

	return true
}

func listNodeGroups(clusterName string, client *eks.EKS, nextToken string) []string {
	// list nodegroups in a specified cluster
	var (
		nodeGroups           []string
		listNodegroupsOutput *eks.ListNodegroupsOutput
		err                  error
	)

	if nextToken == "" {
		listNodegroupsOutput, err = client.ListNodegroups(&eks.ListNodegroupsInput{
			ClusterName: &clusterName,
			MaxResults:  aws.Int64(2),
		})
	} else {
		listNodegroupsOutput, err = client.ListNodegroups(&eks.ListNodegroupsInput{
			ClusterName: &clusterName,
			MaxResults:  aws.Int64(2),
			NextToken:   aws.String(nextToken),
		})
	}

	if err != nil {
		log.Fatalf("%v", err)
	}

	for _, nodeGroupName := range listNodegroupsOutput.Nodegroups {
		nodeGroups = append(nodeGroups, *nodeGroupName)
	}

	if listNodegroupsOutput.NextToken != nil {
		additional := listNodeGroups(clusterName, client, aws.StringValue(listNodegroupsOutput.NextToken))
		for _, nodeGroup := range additional {
			nodeGroups = append(nodeGroups, nodeGroup)
		}
	}

	return nodeGroups
}

func describeNodeGroups(nodeGroups []string, client *eks.EKS) map[string]*eks.Nodegroup {
	// describe a list of nodegroups; returns map
	var (
		nodeGroupsMap            = make(map[string]*eks.Nodegroup)
		describeNodegroupsOutput *eks.DescribeNodegroupOutput
		err                      error
	)

	for _, nodeGroup := range nodeGroups {
		describeNodegroupsOutput, err = client.DescribeNodegroup(&eks.DescribeNodegroupInput{
			ClusterName:   &clusterName,
			NodegroupName: &nodeGroup,
		})
		if err != nil {
			log.Fatalf("%v", err)
		}
		nodeGroupsMap[nodeGroup] = describeNodegroupsOutput.Nodegroup
	}

	return nodeGroupsMap
}

func startSession(config *aws.Config) *session.Session {
	// start a session
	sess, err := session.NewSession(config)
	if err != nil {
		log.Fatalf("%v", err)
	}
	return sess
}

func initConfig() {
	rand.Seed(time.Now().UnixNano())

	// get AWS credentials
	var (
		creds *credentials.Credentials
		err   error
		order []string
		last  []string
	)
	// if env vars are set use them, otherwise use profile
	if isEnvExist("AWS_ACCESS_KEY_ID") || isEnvExist("AWS_SECRET_ACCESS_KEY") {
		creds = credentials.NewEnvCredentials()
	} else if isEnvExist("AWS_PROFILE") {
		creds = credentials.NewSharedCredentials("", os.Getenv("AWS_PROFILE"))
	} else {
		err = fmt.Errorf("Either both 'AWS_ACCESS_KEY_ID' and 'AWS_SECRET_ACCESS_KEY' or 'AWS_PROFILE' are required")
		log.Fatalf("%v", err)
	}

	// Retrieve the credentials value
	credValue, err := creds.Get()
	if err != nil {
		log.Fatalf("%v", err)
	}

	if credValue.AccessKeyID == "" || credValue.SecretAccessKey == "" {
		log.Fatalf("Unable to retrieve AWS credentials")
	} else {
		log.Printf("AWS credentials retrieved")
	}

	awsConfig := aws.NewConfig().
		WithRegion(region).
		WithCredentials(creds).
		WithDisableSSL(false).
		WithMaxRetries(20)

	session := startSession(awsConfig)
	eksClient := eks.New(session)
	if eksClient != nil {
		log.Printf("EKS client initialized")
	}

	if isClusterExist(clusterName, eksClient) {
		log.Printf("Located cluster %s in region %s", clusterName, region)
	} else {
		log.Fatalf("Unable to locate cluser %s in region %s", clusterName, region)
	}

	log.Printf("Dumping nodegroups in cluster %s", clusterName)

	nodeGroups := listNodeGroups(clusterName, eksClient, "")

	if quick == true {
		nodeGroupsDetail := describeNodeGroups(nodeGroups, eksClient)

		for _, ng := range nodeGroupsDetail {
			if *ng.ScalingConfig.DesiredSize == 0 {
				log.Printf("NodeGroup %v has 0 nodes, prioritizing for upgrade", *ng.NodegroupName)
				order = append(order, *ng.NodegroupName)
			} else {
				last = append(last, *ng.NodegroupName)
			}
		}

		for _, i := range last {
			order = append(order, i)
		}
	} else {
		order = nodeGroups
	}

	log.Printf("Pausing until %v state is 'ACTIVE'", clusterName)
	waitUntilActive(60, time.Second, clusterName, eksClient)

	// begin updates
	for _, nodeGroup := range order {
		// wait for cluster to be ready
		log.Printf("Pausing until NodeGroup %v state is 'ACTIVE'", nodeGroup)
		waitUntilUpdateComplete(60, time.Second, nodeGroup, clusterName, eksClient)

		if updateNodeGroup(nodeGroup, clusterName, eksClient) {
			log.Printf("Updated nodegroup %s", nodeGroup)
		}

		// wait for cluster to be ready
		log.Printf("Pausing until NodeGroup %v state is 'ACTIVE'", nodeGroup)
		waitUntilUpdateComplete(60, time.Second, nodeGroup, clusterName, eksClient)
	}

	log.Printf("Updates complete!")
}
