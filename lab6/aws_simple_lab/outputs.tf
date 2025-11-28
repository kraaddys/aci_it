output "ec2_public_ip" {
  description = "Публичный IP-адрес EC2-инстанса"
  value       = aws_instance.web.public_ip
}

output "s3_bucket_name" {
  description = "Имя S3-бакета"
  value       = aws_s3_bucket.files.bucket
}