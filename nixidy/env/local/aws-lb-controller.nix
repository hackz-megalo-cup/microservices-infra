{ charts, ... }:
{
  applications.aws-lb-controller = {
    namespace = "kube-system";

    helm.releases.aws-load-balancer-controller = {
      chart = charts.eks.aws-load-balancer-controller;
      values = {
        clusterName = "microservices-infra-eks";
        region = "ap-northeast-1";

        serviceAccount = {
          create = true;
          name = "aws-load-balancer-controller";
          annotations = {
            "eks.amazonaws.com/role-arn" =
              "arn:aws:iam::860973283109:role/microservices-infra-eks-lb-controller-role";
          };
        };

        # VPC ID is required for the controller to discover subnets
        vpcId = "vpc-0d5df4c32e5c9437f";

        # Enable webhook for TargetGroupBinding CRD
        enableCertManager = false;
      };
    };
  };
}
