terraform {
  backend "gcs" {
    bucket  = "tf-state-gis-dev"
    prefix  = "terraform/state"
  }
}