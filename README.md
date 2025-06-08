# GCP Student Projects

This Terraform configuration creates GCP projects for students based on a CSV file of names.

## Prerequisites

- Terraform installed
- Google Cloud SDK installed and configured
- GCP billing account ID
- GCP project ID for the default project

## Configuration

1. Create a `students.csv` file with student names in the format:
```csv
name
John Smith
Jane Doe
```

2. Configure your GCP credentials in `gcp.auto.tfvars`:
```hcl
gcp_project         = "your-default-project-id"
gcp_billing_account = "your-billing-account-id"
gcp_region          = "us-west1"
```

## Usage

1. Initialize Terraform:
```bash
terraform init
```

2. Review the changes:
```bash
terraform plan
```

3. Apply the configuration:
```bash
terraform apply
```

## What Gets Created

For each student in the CSV file:
- A new GCP project with ID format: `{first_initial}{lastname}-{random_suffix}`
- A service account with Editor role
- Compute Engine API enabled

## Outputs

The configuration outputs:
- List of raw student names from CSV
- Project IDs and service account emails for each student

## Cleanup

To destroy all created resources:
```bash
terraform destroy
``` 