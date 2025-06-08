provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

locals {
  # Load CSV data or use default
  raw_csv       = fileexists("${path.module}/students.csv") ? file("${path.module}/students.csv") : "name\nDefaultStudent"
  raw_students  = csvdecode(local.raw_csv)

  # Build students list with normalized names
  students      = [for student in local.raw_students : {
    name = length(split(" ", student.name)) > 1 ? (
      # For full names (with spaces), use first initial + last name
      join("", [
        lower(substr(split(" ", student.name)[0], 0, 1)),  # First initial
        lower(split(" ", student.name)[length(split(" ", student.name)) - 1])  # Last name
      ])
    ) : (
      # For single names, just convert to lowercase
      lower(student.name)
    )
  }]

  student_count = length(local.students)
}

output "raw_students" {
  value = local.raw_students
}

# Create a new project for each student
resource "google_project" "student_project" {
  for_each = { for idx, student in local.students : student.name => student }

  name            = "${each.value.name}-project"
  project_id      = "${each.value.name}-${random_string.project_suffix[each.key].result}"
  billing_account = var.gcp_billing_account

  labels = {
    student = each.value.name
    purpose = "training"
  }
}

# Generate random suffix for project IDs to ensure uniqueness
resource "random_string" "project_suffix" {
  for_each = { for idx, student in local.students : student.name => student }
  
  length  = 6
  special = false
  upper   = false
}

# Enable required APIs for each project
resource "google_project_service" "project_apis" {
  for_each = { for idx, student in local.students : student.name => student }

  project = google_project.student_project[each.key].project_id
  service = "compute.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy        = false
}

# Create service account for each project
resource "google_service_account" "student_service_account" {
  for_each = { for idx, student in local.students : student.name => student }

  project      = google_project.student_project[each.key].project_id
  account_id   = "${each.value.name}-sa"
  display_name = "Service Account for ${each.value.name}"
}

# Grant necessary roles to service accounts
resource "google_project_iam_member" "service_account_roles" {
  for_each = { for idx, student in local.students : student.name => student }

  project = google_project.student_project[each.key].project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.student_service_account[each.key].email}"
}

# Output the project IDs and service account emails
output "student_projects" {
  value = {
    for student in local.students : student.name => {
      project_id         = google_project.student_project[student.name].project_id
      service_account_email = google_service_account.student_service_account[student.name].email
    }
  }
} 