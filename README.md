# Static Site Deployment to Cloudfront+S3

This is a template for quickly setting up and deploying a static web site to Amazon S3 + Cloudfront CDN. (See [S3 pricing](https://aws.amazon.com/s3/pricing/); [Cloudfront pricing](https://aws.amazon.com/cloudfront/pricing/))

Assumptions:
- An active AWS account
- An IAM user with access to S3, Cloudfront, and CertificateManager
- [AWS CLI](http://docs.aws.amazon.com/cli/latest/userguide/installing.html) is installed
- [Terraform](https://www.terraform.io/intro/getting-started/install.html) is installed

Basic steps:
0. Request a free SSL cert from [AWS Certificate Manager](https://console.aws.amazon.com/acm/home), or upload one.
1. Review the terraform configuration, static.tf, and make changes as needed.
2. Populate your local [AWS credentials](#aws-credentials) file with an IAM user having access to S3, Cloudfront, and CertificateManager
3. Run [terraform commands](#terraform) to provision or update AWS infrastructure
4. [Deploy](#deploy) content using aws-s3-sync

## AWS SSL Certs

You'll need to provision an SSL cert and make it available to the AWS
Certificate Manager. To request a free cert, visit https://console.aws.amazon.com/acm/home.

This process will take some time as you'll need to prove domain ownership.
Docs: https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request.html

Once your certificate status is `Issued`, add its ARN as a terraform variables.

## AWS Credentials

Add your AWS credentials to `$HOME/.aws/credentials`. If using a [named profile](), set the profile name in the [terraform configuration](./static.tf) as `aws_cli_profile`.

## Terraform

See `static.tf` for AWS configuration.

```
$ terraform plan    # dry run
$ terraform apply   # create resources
$ terraform show    # show state
```

When running `apply` or `show`, you'll be prompted to define any needed variables. You can pre-populate variables in a `tfvars` file instead, and use that with the configuration:

```
$ terraform plan -var-file=static.tfvars
```

## Deploy

```
$ aws s3 sync static s3://www.example.com [--profile default] --exclude *.DS_Store --delete
```

## CDN cache invalidation

- [Cache invalidations for web distributions](http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Invalidation.html)
- [CLI reference](http://docs.aws.amazon.com/cli/latest/reference/cloudfront/create-invalidation.html)

## Troubleshooting

- `InvalidClientTokenId`: check the values in `~/.aws/credentials`, and make sure the [correct profile is used](#aws-credentials) (if not default)

## Misc notes

- [HTML5 Bootstrap](http://www.initializr.com)

### JPG compression

- [guetzli](https://github.com/google/guetzli) seems to change color significantly.
- [mozjpeg](https://hacks.mozilla.org/2014/08/using-mozjpeg-to-create-efficient-jpegs/) is reasonable.

```
/usr/local/opt/mozjpeg/bin/cjpeg rocks.jpg -quality 80 > rocks-moz.jpg
```

