output "cluster_name" { description = "EKS cluster name." value = aws_eks_cluster.this.name }
output "cluster_endpoint" { description = "EKS API endpoint." value = aws_eks_cluster.this.endpoint }
