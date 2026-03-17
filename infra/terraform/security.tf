data "aws_security_group" "eks_node" {
  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [aws_eks_cluster.main.name]
  }

  filter {
    name   = "description"
    values = ["EKS created security group applied to ENI that is attached to EKS Control Plane master nodes, as well as any managed workloads.*"]
  }

  depends_on = [aws_eks_node_group.workers]
}

data "aws_security_groups" "eks_node_groups" {
  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [aws_eks_cluster.main.name]
  }

  depends_on = [aws_eks_node_group.workers]
}

# Agones game server ports: TCP+UDP 7000-8000
resource "aws_security_group_rule" "agones_gameserver_tcp" {
  type              = "ingress"
  from_port         = 7000
  to_port           = 8000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = data.aws_security_group.eks_node.id
  description       = "Agones game server TCP passthrough ports"
}

resource "aws_security_group_rule" "agones_gameserver_udp" {
  type              = "ingress"
  from_port         = 7000
  to_port           = 8000
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = data.aws_security_group.eks_node.id
  description       = "Agones game server UDP passthrough ports"
}
