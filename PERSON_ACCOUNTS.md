# Person Accounts

For orgs that store people as Person Accounts (for example credit unions on Financial
Services Cloud). The app detects Person Accounts on its own; in orgs without it, nothing
changes.

## What works where

| Feature | With Person Accounts |
| --- | --- |
| **Person Card** | Add **Extole Person Card** to your Person Account record page in Lightning App Builder. It shows only on Person Accounts and stays hidden on business accounts. Friends who are Person Accounts link to the Account. |
| **Send Extole Events** | Pick **Account** as the trigger object and map `PersonEmail` to `email`. For Opportunity events, map `Account.PersonEmail` to `email` and `Account.PersonContactId` to `partner_user_id` (Opportunities on a Person Account have no primary contact). An Account trigger also fires for business accounts; those events carry no email. |
| **Receive Extole Events** | **Person Account** is an Object Type for a rule. It finds the Person Account by `PersonEmail` and updates it. It never creates one. |
| **Manage Share Links** | Choose **Person Accounts**. For a report audience, the first column must be `ACCOUNT_ID` or `PC_CONTACT_ID`. The link is written to the Account's person field (for example `Extole_Share_Link__pc`). |
| **Manage Audiences** | Use a tabular Accounts report and choose **Person Account: Email** (`PC_EMAIL`) as the identity column. |

## Creating records from sign-ups

On a Receive Extole Events rule, **Create the record if it is not found** creates a Lead or
Contact from the event's email, first name and last name. A missing last name becomes
"Unknown" (Salesforce requires one).

- With Person Accounts on, a created Lead has no Company, so converting it creates a Person
  Account instead of a business account.
- A Lead or Contact is not created when the email already belongs to a Contact or Person
  Account; the log shows SKIPPED with the reason.
- Deliveries for the same email run one at a time, so simultaneous events do not create
  duplicates. If one is still running, the endpoint returns 503 and Extole retries.

## Lead conversion

Custom Lead fields (share link, advocate code) only reach the Person Account if they are
mapped: Setup > Object Manager > Lead > Fields & Relationships > **Map Lead Fields**.
This can't be deployed, so each org sets it once.

## Who shows as the user on changes

Receive Extole Events authenticates with the Client Credentials flow (INSTALL.md, Step 10),
so records the writeback creates or updates show that app's **Run As** user (Created By,
Last Modified By and Owner). Make the Run As user a dedicated integration user with API
access and access to the objects your rules write to, so records don't show a person.

## Not covered yet

- The writeback does not set Lead Source.
- The Manage Share Links **Contacts** option still includes the hidden contacts of Person
  Accounts.
