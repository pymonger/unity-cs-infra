data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "vpc_id" {
  name = "/unity/account/network/vpc_id"
}

data "aws_ssm_parameter" "subnet_list" {
  name = "/unity/account/network/subnet_list"
}

#data "aws_ssm_parameter" "cluster_sg" {
#  name = "/unity/account/eks/cluster_sg"
#}
#
#data "aws_ssm_parameter" "node_sg" {
#  name = "/unity/account/eks/node_sg"
#}

#data "aws_ssm_parameter" "eks_iam_node_role" {
#  name = "/unity/account/eks/eks_iam_node_role"
#}
#
#data "aws_ssm_parameter" "eks_iam_role" {
#  name = "/unity/account/eks/eks_iam_role"
#}

data "aws_ssm_parameter" "eks_ami_1_27" {
  name = "/unity/account/eks/amis/aml2-eks-1-27"
}

data "aws_ssm_parameter" "eks_ami_1_26" {
  name = "/unity/account/eks/amis/aml2-eks-1-26"
}

data "aws_ssm_parameter" "eks_ami_1_25" {
  name = "/unity/account/eks/amis/aml2-eks-1-25"
}
#
#data "aws_ssm_parameter" "eks_ami_1_24" {
#  name = "/unity/account/eks/amis/aml2-eks-1-24"
#}

locals {
  common_tags  = {}
  cluster_name = var.deployment_name
  subnet_map   = jsondecode(data.aws_ssm_parameter.subnet_list.value)
  #ami = "ami-0e3e9697a56f6ba66"
  ami_map = {
    "1.27"    = data.aws_ssm_parameter.eks_ami_1_27.value
    "1.26"    = data.aws_ssm_parameter.eks_ami_1_26.value
    "1.25"    = data.aws_ssm_parameter.eks_ami_1_25.value
    "default" = "ami-0e3e9697a56f6ba66"
  }
  #iam_arn = data.aws_ssm_parameter.eks_iam_node_role.value
  mergednodegroups = { for name, ng in var.nodegroups :
    name => {
      use_name_prefix            = false
      create_iam_role            = false
      min_size                   = ng.min_size != null ? ng.min_size : 1
      max_size                   = ng.max_size != null ? ng.max_size : 10
      desired_size               = ng.desired_size != null ? ng.desired_size : 3
      ami_id                     = ng.ami_id != null ? ng.ami_id : lookup(local.ami_map, var.cluster_version, local.ami_map["default"])
      instance_types             = ng.instance_types != null ? ng.instance_types : ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
      capacity_type              = ng.capacity_type != null ? ng.capacity_type : "ON_DEMAND"
      iam_role_arn               = ng.iam_role_arn != null ? ng.iam_role_arn : aws_iam_role.cluster_iam_role.arn
      enable_bootstrap_user_data = true
      pre_bootstrap_user_data    = <<-EOT
            sudo sed -i 's/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/sysctl.conf && sudo sysctl -p |true
        EOT
      metadata_options = {
        "http_endpoint" : ng.metadata_options != null ? lookup(ng.metadata_options, "http_endpoint", null) : null
        "http_put_response_hop_limit" : ng.metadata_options != null ? lookup(ng.metadata_options, "http_put_response_hop_limit", null) : null
        "http_tokens" : ng.metadata_options != null ? lookup(ng.metadata_options, "http_tokens", null) : null
      }
    }
  }
}


data "aws_iam_policy" "mcp_operator_policy" {
  name = "mcp-tenantOperator-AMI-APIG"
}

resource "aws_iam_role" "cluster_iam_role" {
  name = "${local.cluster_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com" # or the appropriate AWS service
        },
      },
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com" # or the appropriate AWS service
        },
      },
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com" # or the appropriate AWS service
        },
      },
    ],
  })

  permissions_boundary = data.aws_iam_policy.mcp_operator_policy.arn

}


resource "aws_iam_role_policy_attachment" "container-reg" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ebscsi" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
resource "aws_iam_role_policy_attachment" "eks-cni" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "worker-node" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "ssm-automation" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMAutomationRole"
}
resource "aws_iam_role_policy_attachment" "ssm-managed-instance" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "cloudwatch-agent" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
data "aws_iam_policy" "datalakekinesis" {
  name = "DatalakeKinesisPolicy"
}
resource "aws_iam_role_policy_attachment" "kinesis" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = data.aws_iam_policy.datalakekinesis.arn
}

data "aws_iam_policy" "mcptools" {
  name = "McpToolsAccessPolicy"
}

resource "aws_iam_role_policy_attachment" "mcptools" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = data.aws_iam_policy.mcptools.arn
}


resource "aws_iam_role_policy_attachment" "node-policy" {
  role       = aws_iam_role.cluster_iam_role.name
  policy_arn = aws_iam_policy.custom_policy.arn
}

resource "aws_iam_policy" "custom_policy" {
  name        = "${local.cluster_name}-eks-policy" # Give a unique name to your policy
  path        = "/"                                # Optionally, specify a path for the policy
  description = "A custom policy that provides access to EC2, ECR, SNS, etc."

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "ec2:CreateTags",
            "Resource": [
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:snapshot/*"
            ],
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": [
                        "CreateVolume",
                        "CreateSnapshot"
                    ]
                }
            }
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "ec2:CreateVolume",
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "aws:RequestTag/ebs.csi.aws.com/cluster": "true"
                }
            }
        },
        {
            "Sid": "VisualEditor2",
            "Effect": "Allow",
            "Action": "ec2:CreateVolume",
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "aws:RequestTag/CSIVolumeName": "*"
                }
            }
        },
        {
            "Sid": "VisualEditor3",
            "Effect": "Allow",
            "Action": "ec2:DeleteVolume",
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
                }
            }
        },
        {
            "Sid": "VisualEditor4",
            "Effect": "Allow",
            "Action": "ec2:DeleteVolume",
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/CSIVolumeName": "*"
                }
            }
        },
        {
            "Sid": "VisualEditor5",
            "Effect": "Allow",
            "Action": "ec2:DeleteVolume",
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/kubernetes.io/created-for/pvc/name": "*"
                }
            }
        },
        {
            "Sid": "VisualEditor6",
            "Effect": "Allow",
            "Action": "ec2:DeleteSnapshot",
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/CSIVolumeSnapshotName": "*"
                }
            }
        },
        {
            "Sid": "VisualEditor7",
            "Effect": "Allow",
            "Action": "ec2:DeleteSnapshot",
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
                }
            }
        },
        {
            "Sid": "VisualEditor8",
            "Effect": "Allow",
            "Action": "ec2:CreateTags",
            "Resource": "arn:aws:ec2:*:*:network-interface/*"
        },
        {
            "Sid": "VisualEditor9",
            "Effect": "Allow",
            "Action": "ec2:DeleteTags",
            "Resource": [
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:snapshot/*"
            ]
        },
        {
            "Sid": "VisualEditor10",
            "Effect": "Allow",
            "Action": [
                "sns:Publish",
                "lambda:InvokeFunction",
                "ssm:GetParameter"
            ],
            "Resource": [
                "arn:aws:lambda:*:*:function:Automation*",
                "arn:aws:sns:*:*:Automation*",
                "arn:aws:ssm:*:*:parameter/AmazonCloudWatch-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages",
                "ecr:BatchGetImage",
                "ecr:GetLifecyclePolicy",
                "ecr:GetLifecyclePolicyPreview",
                "ecr:ListTagsForResource",
                "ecr:DescribeImageScanFindings"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor11",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "cloudwatch:PutMetricData",
                "ec2:DescribeVolumesModifications",
                "ec2:CreateImage",
                "ec2:CopyImage",
                "ssm:ListInstanceAssociations",
                "ec2:DescribeSnapshots",
                "ssm:GetParameter",
                "ssm:UpdateAssociationStatus",
                "logs:CreateLogStream",
                "cloudformation:DescribeStackEvents",
                "ec2:StartInstances",
                "ssm:UpdateInstanceInformation",
                "ec2:DescribeVolumes",
                "cloudformation:UpdateStack",
                "ec2:UnassignPrivateIpAddresses",
                "ec2:DescribeRouteTables",
                "ssm:PutComplianceItems",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetLifecyclePolicy",
                "ec2:DetachVolume",
                "sns:*",
                "ec2:ModifyVolume",
                "ecr:DescribeImageScanFindings",
                "ec2:CreateTags",
                "ec2:ModifyNetworkInterfaceAttribute",
                "ecr:GetDownloadUrlForLayer",
                "ec2:DeleteNetworkInterface",
                "ec2messages:AcknowledgeMessage",
                "ec2:RunInstances",
                "ecr:GetAuthorizationToken",
                "ssm:GetParameters",
                "ec2:StopInstances",
                "s3-object-lambda:*",
                "ec2:AssignPrivateIpAddresses",
                "logs:CreateLogGroup",
                "cloudformation:DescribeStacks",
                "ec2:CreateNetworkInterface",
                "cloudformation:DeleteStack",
                "ec2:DescribeInstanceTypes",
                "ecr:BatchGetImage",
                "ecr:DescribeImages",
                "ec2messages:SendReply",
                "eks:DescribeCluster",
                "ec2:DescribeSubnets",
                "ec2:AttachVolume",
                "ec2:DeregisterImage",
                "ec2:DeleteSnapshot",
                "ssm:DescribeDocument",
                "ec2:DeleteTags",
                "ec2messages:GetEndpoint",
                "logs:DescribeLogStreams",
                "ssmmessages:OpenControlChannel",
                "ec2messages:GetMessages",
                "ecr:ListTagsForResource",
                "ssm:PutConfigurePackageResult",
                "ecr:ListImages",
                "ssm:GetManifest",
                "ec2messages:DeleteMessage",
                "ec2:DescribeNetworkInterfaces",
                "ec2messages:FailMessage",
                "ec2:DescribeAvailabilityZones",
                "ssmmessages:OpenDataChannel",
                "ec2:CreateSnapshot",
                "ssm:GetDocument",
                "ecr:DescribeRepositories",
                "ec2:DescribeInstanceStatus",
                "ssm:DescribeAssociation",
                "ec2:TerminateInstances",
                "ec2:DetachNetworkInterface",
                "logs:DescribeLogGroups",
                "ssm:GetDeployablePatchSnapshotForInstance",
                "s3:*",
                "ec2:DescribeTags",
                "ecr:GetLifecyclePolicyPreview",
                "ssmmessages:CreateControlChannel",
                "logs:PutLogEvents",
                "ec2:DescribeSecurityGroups",
                "ssmmessages:CreateDataChannel",
                "ec2:DescribeImages",
                "ssm:PutInventory",
                "cloudformation:CreateStack",
                "ec2:DescribeVpcs",
                "ssm:*",
                "ec2:AttachNetworkInterface",
                "ssm:ListAssociations",
                "ssm:UpdateInstanceAssociationStatus",
                "ecr:GetRepositoryPolicy"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.16.0"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
  }

  subnet_ids = local.subnet_map["private"]

  vpc_id = data.aws_ssm_parameter.vpc_id.value

  #cluster_security_group_id = data.aws_ssm_parameter.cluster_sg.value
  create_cluster_security_group = true
  create_node_security_group    = true
  create_iam_role               = false
  enable_irsa                   = true
  iam_role_arn                  = aws_iam_role.cluster_iam_role.arn
  #node_security_group_id = data.aws_ssm_parameter.node_sg.value

  eks_managed_node_group_defaults = {
    instance_types = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
    iam_role_arn   = aws_iam_role.cluster_iam_role.arn
  }

  eks_managed_node_groups = local.mergednodegroups

  aws_auth_roles                  = var.aws_auth_roles
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  tags                            = var.tags
}

resource "aws_launch_template" "node_group_launch_template" {
  image_id = "ami-0e3e9697a56f6ba66"
  name     = "eks-${local.cluster_name}-nodeGroup-launchTemplate"
  user_data = base64encode(<<EOT
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh ${local.cluster_name}
  EOT
  )
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name      = "${local.cluster_name} Node Group Node"
      Component = "EKS EC2 Instance"
      Stack     = "EKS EC2 Instance"
    })
  }
}


# TODO: select default node group more intelligently, or remove concept altogether
resource "aws_ssm_parameter" "node_group_default_launch_template_name" {
  name  = "/unity/extensions/eks/${local.cluster_name}/nodeGroups/default/launchTemplateName"
  type  = "String"
  value = aws_launch_template.node_group_launch_template.name
}

resource "aws_ssm_parameter" "node_group_default_name" {
  name = "/unity/extensions/eks/${var.deployment_name}/nodeGroups/default/name"
  type = "String"
  # Get name of first nodegroup in nodegroup map variable
  value = keys(var.nodegroups)[0]
  # Get first nodegroup name from keys of node group variable and use it to
  # value = split(":", aws_eks_node_group.node_groups[keys(var.node_groups)[0]].id)[0]
}

resource "aws_ssm_parameter" "eks_subnets" {
  name  = "/unity/extensions/eks/${local.cluster_name}/networking/subnets/publicIds"
  type  = "String"
  value = join(",", local.subnet_map["private"])
}

data "aws_iam_policy" "ebs_csi_policy" {
  name = "U-CS_Service_Policy"
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }

}

resource "helm_release" "aws-load-balancer-controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.1"
  namespace  = "kube-system"
  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  depends_on = [module.eks.eks_managed_node_groups]
}

resource "kubernetes_service_account" "aws-load-balancer-controller-service-account" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" : aws_iam_role.aws-load-balancer-controller-role.arn
    }
    labels = {
      "app.kubernetes.io/component" : "controller"
      "app.kubernetes.io/name" : "aws-load-balancer-controller"
    }
  }
}

locals {
  openidc_provider_domain_name = trimprefix(module.eks.cluster_oidc_issuer_url, "https://")
}

data "aws_iam_policy" "aws-managed-load-balancer-policy" {
  arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

# AwsLoadBalancerController Role and Policy from https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
resource "aws_iam_role" "aws-load-balancer-controller-role" {
  name = "AwsLoadBalancerControllerRole-${local.cluster_name}"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.openidc_provider_domain_name}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${local.openidc_provider_domain_name}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller",
            "${local.openidc_provider_domain_name}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  managed_policy_arns  = [aws_iam_policy.aws-load-balancer-controller-policy.arn]
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/mcp-tenantOperator-AMI-APIG"
}

resource "aws_iam_role_policy_attachment" "aws-load-balancer-policy-attachment" {
  role       = aws_iam_role.aws-load-balancer-controller-role.name
  policy_arn = data.aws_iam_policy.aws-managed-load-balancer-policy.arn
}

resource "aws_iam_policy" "aws-load-balancer-controller-policy" {
  name = "AwsLoadBalancerControllerPolicy-${local.cluster_name}"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateServiceLinkedRole"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "iam:AWSServiceName" : "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateSecurityGroup"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateTags"
        ],
        "Resource" : "arn:aws:ec2:*:*:security-group/*",
        "Condition" : {
          "StringEquals" : {
            "ec2:CreateAction" : "CreateSecurityGroup"
          },
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        "Resource" : "arn:aws:ec2:*:*:security-group/*",
        "Condition" : {
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "true",
            "aws:ResourceTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ],
        "Resource" : "*",
        "Condition" : {
          "Null" : {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ],
        "Resource" : "*",
        "Condition" : {
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ],
        "Condition" : {
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "true",
            "aws:ResourceTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ],
        "Resource" : "*",
        "Condition" : {
          "Null" : {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:AddTags"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ],
        "Condition" : {
          "StringEquals" : {
            "elasticloadbalancing:CreateAction" : [
              "CreateTargetGroup",
              "CreateLoadBalancer"
            ]
          },
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ],
        "Resource" : "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ],
        "Resource" : "*"
      }
    ]
  })
}


#module "irsa-ebs-csi" {
#  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#  version = "4.7.0"
#
#  create_role                   = false
#  #role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
#  role_name = "U-CS_Service_Role"
#  provider_url                  = module.eks.oidc_provider
#  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
#  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
#}

#resource "aws_eks_addon" "ebs-csi" {
#  cluster_name             = module.eks.cluster_name
#  addon_name               = "aws-ebs-csi-driver"
#  addon_version            = "v1.20.0-eksbuild.1"
#  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
#  tags = {
#    "eks_addon" = "ebs-csi"
#    "terraform" = "true"
#  }
#}
