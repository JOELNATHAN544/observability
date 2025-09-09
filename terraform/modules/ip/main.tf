resource "google_compute_address" "default" {
  name         = "${var.name}-ip"
  region       = var.region
  project      = var.project_id
  address_type = "EXTERNAL"
}