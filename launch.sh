#!/bin/bash

sudo ./Launch-setup/cleanup.sh

mapfile -t instanceARP < <(aws ec2 run-instances  --image-id $1 --count $2 --instance-type $3  --security-group-ids $4 --subnet-id $5 --key-name $6 --associate-public-ip-address --iam-instance-profile $7 --user-data file://Environment-setup/install-env.sh --output table | grep InstanceID | sed "s/|//g" | tr -d ' '| sed "s/ InstanceId//g")

echo "${#instanceARP[@]}"

aws ec2 wait instance-running --instance-ids ${instanceARP[@]}
echo "${#instance[@]}"
echo "I'm Ready, instance are running"

aws elb create-load-balancer --load-balancer-name itmo-444-et-lb --listeners Protocl=HTTP.LoadBalancerPort=80, InstanceProtocol=HTTP, InstancePort=80 --security-group-ids $4 --subnet-id $5 --output=text 



echo -e "\nFinished launching ELB and sleeping 30 seconds"
for i in {0..30}; do echo -ne '.';sleep 1;done
echo "\n"


aws elb register-instances-with-load-balancer --load-balancer-name itmo-444-et-lb --instances ${instanceARR[@]}

aws elb configure-health-check --load-balancer-name itmo-444-et-lb --health-check Target=HTTP:80/index.html,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3

aws autoscaling create-launch-configuration --launch-configuration-name et-itmo-444-launch-config --image-id $1 --key-name $6 --security-groups $4 --instance-type $3 --user-data file://Environment-setup/install-webserver.sh --iam-instance-profile $7

aws cloudwatch put-metric-alarm --alarm-name et-AddCapacity --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 120 --threshold 30 --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=AutoScalingGroupName,Value=my-asg" --evaluation-periods 2 --alarm-actions PolicyARN 

aws cloudwatch put-metric-alarm --alarm-name et-RemoveCapacity --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 120 --threshold 10 --comparison-operator LessThanOrEqualToThreshold  --dimensions "Name=AutoScalingGroupName,Value=my-asg" --evaluation-periods 2 --alarm-actions PolicyARN 

aws autoscaling create-auto-scaling-group --auto-scaling-group-name et-itmo-444-extended-auto-scaling-group-2 --launch-configuration-name itmo444-launch-config --load-balancer-names ET-lb  --health-check-type ELB --min-size 3 --max-size 6 --desired-capacity 3 --default-cooldown 600 --health-check-grace-period 120 

mapfile -t dbInstanceARR < <(aws rds describe-db-instances --output json | grep "\"DBInstanceIdentifier" | sed "s/[\"\:\, ]//g" | sed "s/DBInstanceIdentifier//g" )

if [ ${#dbInstanceARR[@]} -gt 0 ]
   then
   echo "Deleting existing RDS database-instances"
   LENGTH=${#dbInstanceARR[@]}

      for (( i=0; i<${LENGTH}; i++));
      do
      if [ ${dbInstanceARR[i]} == "et-db" ] 
     then 
      echo "db exists"
     else
     aws rds create-db-instance --db-instance-identifier et-db --db-instance-class db.t1.micro --engine MySQL --master-username et-itmo-444 --master-user-password letmein --allocated-storage 5
      fi  
     done
fi
