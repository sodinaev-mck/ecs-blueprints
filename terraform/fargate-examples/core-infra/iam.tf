data "aws_iam_policy" "ssmcore" {
  name = "AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy" "ecr_full" {
  name = "AmazonEC2ContainerRegistryFullAccess"
}


resource "aws_iam_role" "ssm" {
  name = "${var.app_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = [
    data.aws_iam_policy.ssmcore.arn,
    data.aws_iam_policy.ecr_full.arn,
  ]
}

resource "aws_iam_instance_profile" "test_profile" {
  name = aws_iam_role.ssm.name
  role = aws_iam_role.ssm.name
}