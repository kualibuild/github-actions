/*
Copyright © 2022 Cameron Larsen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
package cmd

import (
	"context"
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/google/go-github/v45/github"
	"github.com/spf13/cobra"
	"golang.org/x/oauth2"
)

// rootCmd represents the base command when called without any subcommands
var (
	reviewer  string
	debug     bool
	ownerRepo []string
	pr        []string
	number    int
	client    *github.Client

	rootCmd = &cobra.Command{
		Use:   "aapr",
		Short: "Assigns PRs to the creator and adds the specified teams or users as reviewers",
		Long: `A CLI tool to be used with github actions to assign PRs to the creator and add the 
specified teams/users as reviewers. teams/users must be comma-delimited, and for
teams the required value is the slug. For example:

aapr KualiCo/student-engineering,cam3ron2,regality`,
		Args:       cobra.ExactArgs(1),
		ArgAliases: []string{"reviewer"},
		Run: func(cmd *cobra.Command, args []string) {
			reviewer = args[0]
			checkHasAssignee(0)
			assignReview(reviewer)
		},
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
	rootCmd.PersistentFlags().BoolVar(&debug, "debug", false, "Print debug output")
	cobra.OnInitialize(initConfig)
}

func initConfig() {
	// require token for authentication
	err := 0
	if !isEnvExist("GITHUB_TOKEN") {
		err += 1
		log.Printf("%v", "ERR: GITHUB_TOKEN environment variable is not set")
	}
	// require owner/repo_name
	if !isEnvExist("GITHUB_REPOSITORY") {
		err += 1
		log.Printf("%v", "ERR: GITHUB_REPOSITORY environment variable is not set")
	}
	// set when the event that triggers a workflow run is a pull request
	if !isEnvExist("GITHUB_BASE_REF") {
		err += 1
		log.Printf("%v", "ERR: GITHUB_BASE_REF environment variable is not set")
	}
	// for pull requests this is set to 'refs/pull/<pr_number>/merge'
	if !isEnvExist("GITHUB_REF") {
		err += 1
		log.Printf("%v", "ERR: GITHUB_REF environment variable is not set")
	}
	if err > 0 {
		log.Fatalf("%v", "ERR: one or more environment variables are not set. Exiting.")
	}
	ownerRepo = strings.Split(os.Getenv("GITHUB_REPOSITORY"), "/")
	pr = strings.Split(os.Getenv("GITHUB_REF"), "/")
	number, _ = strconv.Atoi(pr[2])
	client = createClient()
	if client == nil {
		log.Fatalf("%v", "Unable to initialize github client")
	}
}

func isEnvExist(key string) bool {
	// verify if env var is set
	if _, ok := os.LookupEnv(key); ok {
		return true
	}
	return false
}

func isTeam(target string) bool {
	if strings.Contains(target, "/") {
		return true
	}
	return false
}

func createClient() *github.Client {
	// create github client
	ctx := context.Background()
	ts := oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: os.Getenv("GITHUB_TOKEN")},
	)
	tc := oauth2.NewClient(ctx, ts)

	client := github.NewClient(tc)
	user, resp, err := client.Users.Get(ctx, "")
	if err != nil {
		log.Fatalf("error: %v", err)
	}
	log.Printf("API Rate Limit: %#v", resp.Rate.Limit)
	log.Printf("---> Remaining: %#v", resp.Rate.Remaining)
	if !resp.TokenExpiration.IsZero() {
		log.Printf("Token Expiration: %v\n", resp.TokenExpiration)
	}
	if debug {
		log.Printf("Logged in as:%v", *user.Login)
		log.Printf("---> User ID:%v", *user.ID)
		log.Printf("---> URL:%v", *user.URL)
	}
	return client
}

func checkTeamExists(target string) (bool, string) {
	// check target team exists
	// need to add validation to ensure string contains exactly one '/'
	if debug {
		log.Printf("Searching for Team '%v'", target)
	}
	strs := strings.Split(target, "/")
	ctx := context.Background()
	team, _, err := client.Teams.GetTeamBySlug(ctx, ownerRepo[0], strs[1])
	if err != nil {
		log.Fatalf("---> Unable to locate Team '%v'", team)
	}
	if debug {
		log.Printf("---> Team '%v' located, ID: %v", target, *team.ID)
	}
	return true, *team.Name
}

func checkUserExists(target string) (bool, string) {
	// check if reviewer exists
	if debug {
		log.Printf("Searching for User '%v'", target)
	}
	ctx := context.Background()
	user, _, err := client.Users.Get(ctx, target)
	if err != nil {
		log.Fatalf("---> Unable to locate User '%v'", target)
	}
	if debug {
		log.Printf("---> User '%v' located, ID: %v", target, *user.ID)
	}
	return true, *user.Login
}

func requestReview(users []string, teams []string) {
	// request review for PR
	ctx := context.Background()
	reviewRequest := &github.ReviewersRequest{
		Reviewers:     users,
		TeamReviewers: teams,
	}

	_, _, err := client.PullRequests.RequestReviewers(ctx, ownerRepo[0], ownerRepo[1], number, *reviewRequest)

	if err != nil {
		log.Printf("Error: %v", err)
		log.Fatalf("Unable to request review for PR: %v", pr[2])
	}
	if debug {
		log.Printf("Requested review for PR: %v", pr[2])
	}
}

func assignPull(owner string) {
	// update PR owner
	log.Printf("Assigning PR %v to: %v", pr[2], owner)
	ctx := context.Background()
	request := &github.IssueRequest{
		Assignee: &owner,
	}
	_, _, err := client.Issues.Edit(ctx, ownerRepo[0], ownerRepo[1], number, request)
	if err != nil {
		log.Printf("Error: %v", err)
		log.Fatalf("Unable to assign PR: %v", pr[2])
	}
	checkHasAssignee(1)
}

func checkHasAssignee(c int8) {
	log.Printf("Pull Request: %v", pr[2])
	ctx := context.Background()
	resp, _, err := client.PullRequests.Get(ctx, ownerRepo[0], ownerRepo[1], number)
	if err != nil {
		log.Printf("Error: %v", err)
		log.Fatalf("Unable to get PR: %v", pr[2])
	}
	createdby := resp.User
	if createdby == nil {
		log.Printf("---> Opened By: %v", createdby)
	} else {
		log.Printf("---> Opened By: %v", *createdby.Login)
	}
	assignedTo := resp.Assignee
	if assignedTo == nil {
		log.Printf("---> Assigned To: %v", assignedTo)
		if c == 0 {
			assignPull(*createdby.Login)
		} else {
			log.Printf("---> Unable to assgin PR: %v", pr[2])
		}
	} else {
		log.Printf("---> Assigned To: %v", *assignedTo.Login)
	}
}

func assignReview(reviewers string) {
	reviewer := strings.Split(reviewers, ",")
	users := []string{}
	teams := []string{}
	for _, r := range reviewer {
		if isTeam(r) {
			_, id := checkTeamExists(r)
			teams = append(teams, id)
		} else {
			_, id := checkUserExists(r)
			users = append(users, id)
		}
	}

	if debug {
		log.Printf("Assigning to Users: %v", users)
		log.Printf("Assigning to Teams: %v", teams)
	}
	requestReview(users, teams)
}
