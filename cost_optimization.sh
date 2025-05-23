#!/bin/bash

# Fetch all AWS regions
regions=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

# Define a function for each section
save_ec2_details() {
  output_file="ec2_instance_details.csv"
  echo "S. No,Account ID,Region,Name,InstanceID,State,ImageID,InstanceType,VPC,Subnet,PrivateIP,VolumeID,SecurityGroupID,AZ" > "$output_file"
  account_id=$(aws sts get-caller-identity --query Account --output text)
  for region in $regions; do
    aws ec2 describe-instances --region "$region" --query "Reservations[*].Instances[*].{
      Name: Tags[?Key=='Name'] | [0].Value,
      InstanceID: InstanceId,
      State: State.Name,
      ImageID: ImageId,
      InstanceType: InstanceType,
      VPC: VpcId,
      Subnet: SubnetId,
      PrivateIP: PrivateIpAddress,
      VolumeID: BlockDeviceMappings[0].Ebs.VolumeId,
      SecurityGroupID: SecurityGroups[0].GroupId,
      AZ: Placement.AvailabilityZone
    }" --output text | tr '\t' ',' > temp_instances.csv
    awk -v acct="$account_id" -v reg="$region" -F',' '{print NR "," acct "," reg "," $0}' temp_instances.csv >> "$output_file"
    rm -f temp_instances.csv
  done
  echo "✅ EC2 instance details saved to: $output_file"
}

save_ami_details() {
  output_file="ami_details.csv"
  echo "S. No,Account ID,ImageId,Name,Description,Region,CreationDate,SnapshotId" > "$output_file"
  account_id=$(aws sts get-caller-identity --query Account --output text)
  for region in $regions; do
    aws ec2 describe-images --owners self --region "$region" --query "Images[*].[ImageId,Name,Description,CreationDate,BlockDeviceMappings[0].Ebs.SnapshotId]" --output text | tr '\t' ',' > temp_amis.csv
    awk -v acct="$account_id" -v reg="$region" -F',' '{print NR "," acct "," $1 "," $2 "," $3 "," reg "," $4 "," $5}' temp_amis.csv >> "$output_file"
    rm -f temp_amis.csv
  done
  echo "✅ AMI details saved to: $output_file"
}

save_volume_details() {
  output_file="volume_details.csv"
  echo "S. No,Account ID,Region,ID,Size,Type,AZ,State" > "$output_file"
  account_id=$(aws sts get-caller-identity --query Account --output text)
  for region in $regions; do
    aws ec2 describe-volumes --region "$region" --query "Volumes[*].[VolumeId,Size,VolumeType,AvailabilityZone,State]" --output text | tr '\t' ',' > temp_volumes.csv
    awk -v acct="$account_id" -v reg="$region" -F',' '{print NR "," acct "," reg "," $0}' temp_volumes.csv >> "$output_file"
    rm -f temp_volumes.csv
  done
  echo "✅ Volume details saved to: $output_file"
}

save_snapshot_details() {
  output_file="snapshot_details.csv"
  echo "S. No,Account ID,Region,SnapshotId,VolumeId,StartTime,State,Description,Volume Size(GB),Type" > "$output_file"
  account_id=$(aws sts get-caller-identity --query Account --output text)
  sno=1
  for region in $regions; do
    aws ec2 describe-snapshots --owner-ids self --region "$region" \
      --query "Snapshots[*].[SnapshotId,VolumeId,StartTime,State,Description,VolumeSize]" --output text | tr '\t' ',' > temp_snapshots.csv
    while IFS=',' read -r snapshot_id volume_id start_time state description size; do
      vol_type=$(aws ec2 describe-volumes --region "$region" --volume-ids "$volume_id" --query "Volumes[0].VolumeType" --output text 2>/dev/null)
      [[ "$vol_type" == "None" || -z "$vol_type" ]] && vol_type="unknown"
      echo "$sno,$account_id,$region,$snapshot_id,$volume_id,$start_time,$state,\"$description\",$size,$vol_type" >> "$output_file"
      ((sno++))
    done < temp_snapshots.csv
    rm -f temp_snapshots.csv
  done
  echo "✅ Snapshot details saved to: $output_file"
}

save_vpc_details() {
  output_file="vpc_details.csv"
  echo "S. No,Account ID,Region,VpcId,CidrBlock,State,IsDefault,InstanceTenancy,DhcpOptionsId,Name" > "$output_file"
  account_id=$(aws sts get-caller-identity --query Account --output text)
  for region in $regions; do
    aws ec2 describe-vpcs --region "$region" \
      --query "Vpcs[*].[VpcId,CidrBlock,State,IsDefault,InstanceTenancy,DhcpOptionsId,Tags[?Key=='Name']|[0].Value]" --output text | tr '\t' ',' > temp_vpcs.csv
    awk -v acct="$account_id" -v reg="$region" -F',' '{print NR "," acct "," reg "," $0}' temp_vpcs.csv >> "$output_file"
    rm -f temp_vpcs.csv
  done
  echo "✅ VPC details saved to: $output_file"
}

save_rds_details() {
  output_file="rds_details.csv"
  echo "S. No,Account ID,Region,DBInstanceIdentifier,DBInstanceClass,Engine,EngineVersion,DBName,Endpoint,AllocatedStorage,StorageType,AvailabilityZone,MultiAZ,Status" > "$output_file"
  account_id=$(aws sts get-caller-identity --query Account --output text)
  for region in $regions; do
    aws rds describe-db-instances --region "$region" \
      --query "DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,EngineVersion,DBName,Endpoint.Address,AllocatedStorage,StorageType,AvailabilityZone,MultiAZ,DBInstanceStatus]" --output text | tr '\t' ',' > temp_rds.csv
    awk -v acct="$account_id" -v reg="$region" -F',' '{print NR "," acct "," reg "," $0}' temp_rds.csv >> "$output_file"
    rm -f temp_rds.csv
  done
  echo "✅ RDS instance details saved to: $output_file"
}

save_s3_details() {
  output_file="s3_bucket_details.csv"
  account_id=$(aws sts get-caller-identity --query Account --output text)
  echo "S. No,Account ID,BucketName,CreationDate,Region,TotalSizeMB,ObjectCount" > "$output_file"
  bucket_names=$(aws s3api list-buckets --query "Buckets[*].Name" --output text)
  sno=1
  for bucket in $bucket_names; do
    creation_date=$(aws s3api list-buckets --query "Buckets[?Name=='$bucket'].CreationDate" --output text)
    region=$(aws s3api get-bucket-location --bucket "$bucket" --query "LocationConstraint" --output text)
    [[ "$region" == "None" || -z "$region" ]] && region="us-east-1"
    total_size_bytes=$(aws s3api list-objects-v2 --bucket "$bucket" --region "$region" --query "Contents[].Size" --output text | awk '{s+=$1} END {print s}')
    [[ -z "$total_size_bytes" ]] && total_size_bytes=0
    total_size_mb=$(awk "BEGIN {printf \"%.2f\", $total_size_bytes/1024/1024}")
    object_count=$(aws s3api list-objects-v2 --bucket "$bucket" --region "$region" --query "Contents" --output text | wc -l)
    echo "$sno,$account_id,$bucket,$creation_date,$region,$total_size_mb,$object_count" >> "$output_file"
    ((sno++))
  done
  echo "✅ S3 bucket details saved to: $output_file"
}

save_alb_details() {
  output_file="elb_details.csv"
  account_id=$(aws sts get-caller-identity --query Account --output text)
  echo "S. No,Account ID,Region,LoadBalancerType,LoadBalancerName,CreatedTime,Scheme,VpcId,ListenerPort,TargetGroupName" > "$output_file"
  sno=1
  for region in $regions; do
    load_balancers=$(aws elbv2 describe-load-balancers --region "$region" --query "LoadBalancers[*].[Type,LoadBalancerName,CreatedTime,Scheme,VpcId,LoadBalancerArn]" --output json)
    echo "$load_balancers" | jq -c '.[]' | while read -r lb; do
      lb_type=$(echo "$lb" | jq -r '.[0]')
      lb_name=$(echo "$lb" | jq -r '.[1]')
      created_time=$(echo "$lb" | jq -r '.[2]')
      scheme=$(echo "$lb" | jq -r '.[3]')
      vpc_id=$(echo "$lb" | jq -r '.[4]')
      lb_arn=$(echo "$lb" | jq -r '.[5]')
      listeners=$(aws elbv2 describe-listeners --region "$region" --load-balancer-arn "$lb_arn" --query "Listeners[*].ListenerArn" --output text)
      for listener in $listeners; do
        port=$(aws elbv2 describe-listeners --region "$region" --listener-arns "$listener" --query "Listeners[0].Port" --output text)
        rules=$(aws elbv2 describe-rules --region "$region" --listener-arn "$listener" --output json)
        echo "$rules" | jq -c '.Rules[]' | while read -r rule; do
          tg_arn=$(echo "$rule" | jq -r '.Actions[0].TargetGroupArn // empty')
          if [[ -n "$tg_arn" ]]; then
            tg_name=$(aws elbv2 describe-target-groups --region "$region" --target-group-arns "$tg_arn" --query "TargetGroups[0].TargetGroupName" --output text)
            echo "$sno,$account_id,$region,$lb_type,$lb_name,$created_time,$scheme,$vpc_id,$port,$tg_name" >> "$output_file"
            ((sno++))
          fi
        done
      done
    done
  done
  echo "✅ ELB details saved to: $output_file"
}

# Function list
functions=(
  save_ec2_details
  save_ami_details
  save_volume_details
  save_snapshot_details
  save_vpc_details
  save_rds_details
  save_s3_details
  save_alb_details
)

# Run each function
total=${#functions[@]}
count=0
for func in "${functions[@]}"; do
  ((count++))
  echo "🔄 Running [$count/$total] $func... ($(awk "BEGIN {printf \"%.0f\", ($count/$total)*100}")%)"
  $func
done

# Merge to Excel
python3 <<EOF
import pandas as pd
import os

csv_to_sheet = {
    "ec2_instance_details.csv": "EC2 Instances",
    "ami_details.csv": "AMIs",
    "volume_details.csv": "Volumes",
    "snapshot_details.csv": "Snapshots",
    "vpc_details.csv": "VPCs",
    "rds_details.csv": "RDS Instances",
    "s3_bucket_details.csv": "S3 Buckets",
    "elb_details.csv": "ELBs"
}

with pd.ExcelWriter("aws_details.xlsx", engine="openpyxl") as writer:
    for csv_file, sheet_name in csv_to_sheet.items():
        if os.path.exists(csv_file):
            try:
                df = pd.read_csv(csv_file)
                df.to_excel(writer, sheet_name=sheet_name, index=False)
                print(f"✅ Added {sheet_name}")
            except Exception as e:
                print(f"❌ Failed to add {sheet_name}: {e}")
        else:
            print(f"⚠️ File missing: {csv_file}")

print("✅ All CSV files have been merged into aws_details.xlsx")
EOF
