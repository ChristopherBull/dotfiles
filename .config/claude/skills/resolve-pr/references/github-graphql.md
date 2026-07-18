# GitHub review-thread commands

`gh pr` has no built-in command for listing unresolved review threads or resolving them — these need the GraphQL API (`gh api graphql`) or, for replies, the REST API.

## List review threads (and which are unresolved)

```
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
        nodes {
          id
          isResolved
          comments(first:50) {
            nodes { id databaseId body author { login } url }
          }
        }
      }
    }
  }
}' -f owner=OWNER -f repo=REPO -F pr=PR_NUMBER
```

Filter the result for `isResolved: false` — those are the ones that still need action. Each thread's first comment is generally the one to reply to.

## Reply to an inline review comment

Use the REST API with the comment's `databaseId` from the query above:

```
gh api repos/OWNER/REPO/pulls/PR_NUMBER/comments/COMMENT_DATABASE_ID/replies \
  -f body="Fixed in <short-sha> — <one-line description of the change>."
```

## Resolve a thread

Use the thread's GraphQL `id` (not `databaseId`):

```
gh api graphql -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) {
    thread { id isResolved }
  }
}' -f threadId=THREAD_ID
```

## General (non-inline) PR conversation comments

These aren't review threads and don't need resolving, but may still ask for changes worth checking:

```
gh pr view PR_NUMBER --json comments
gh pr comment PR_NUMBER --body "..."
```

## Failing check logs

```
gh pr checks PR_NUMBER --json name,state,link
gh run view RUN_ID --log-failed
```
`RUN_ID` can be pulled from the `link` field above, or via `gh run list --branch <branch-name>`.
