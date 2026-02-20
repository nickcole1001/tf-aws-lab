terraform {
  backend "s3" {
    bucket         = "nickcole1001-tfstate--eu-west-2"
    key            = "tf-aws-lab/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}