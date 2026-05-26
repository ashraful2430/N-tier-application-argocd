data "aws_iam_policy_document" "eks_assume" { statement { actions = ["sts:AssumeRole"] principals { type = "Service" identifiers = ["eks.amazonaws.com"] } } }
resource "aws_iam_role" "cluster" { name = "${var.project_name}-eks-cluster" assume_role_policy = data.aws_iam_policy_document.eks_assume.json }
resource "aws_iam_role_policy_attachment" "cluster" { role = aws_iam_role.cluster.name policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" }
data "aws_iam_policy_document" "node_assume" { statement { actions = ["sts:AssumeRole"] principals { type = "Service" identifiers = ["ec2.amazonaws.com"] } } }
resource "aws_iam_role" "node" { name = "${var.project_name}-eks-node" assume_role_policy = data.aws_iam_policy_document.node_assume.json }
resource "aws_iam_role_policy_attachment" "node_worker" { role = aws_iam_role.node.name policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" }
resource "aws_iam_role_policy_attachment" "node_cni" { role = aws_iam_role.node.name policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" }
resource "aws_iam_role_policy_attachment" "node_registry" { role = aws_iam_role.node.name policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" }
