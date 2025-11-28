# 📘 Лабораторная работа №6

## **Простое развертывание EC2 и S3 на AWS с Terraform**

### **Цель работы**

Изучить процесс создания базовой инфраструктуры в AWS с помощью Terraform, включая:

* развёртывание виртуальной машины EC2,
* создание S3-бакета,
* использование переменных и выходных данных,
* хранение Terraform state в удалённом backend (S3).

---

# 1. Подготовка проекта и окружения к нему

### Создание EC2 и S3 Bucket в AWS

Все создается в регионе `eu-central-1`.

Для начала создается EC2.

![image](https://i.imgur.com/DkVomPJ.png)

![image](https://i.imgur.com/E2z2Ekv.png)

Затем создается S3 Bucket.

![image](https://i.imgur.com/j5xCH3i.png)

![image](https://i.imgur.com/0tpjC3v.png)

### Создание структуры проекта:

```bash
mkdir aws_simple_lab
cd aws_simple_lab
```

Созданы файлы:

* `main.tf`
* `variables.tf`
* `outputs.tf`
* `terraform.tfvars`

# 2. Конфигурационные файлы Terraform

## **2.1 main.tf**

```hcl
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "my-tf-state-simple-k18"    
    key     = "aws_simple_lab/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# -------- EC2-инстанс --------
resource "aws_instance" "web" {
  ami           = "ami-0a6793a25df710b06"
  instance_type = "t3.micro"

  tags = {
    Name = "WebServer-${var.env}"
  }
}

# -------- S3-бакет --------
resource "aws_s3_bucket" "files" {
  bucket = "my-simple-bucket-${var.env}-k18"
}
```

## **2.2 variables.tf**

```hcl
variable "aws_region" {
  description = "Регион AWS для развёртывания ресурсов"
  type        = string
  default     = "eu-central-1"
}

variable "env" {
  description = "Окружение (dev / stage / prod)"
  type        = string
  default     = "dev"
}
```

## **2.3 terraform.tfvars**

```hcl
aws_region = "eu-central-1"
env        = "dev"
```

## **2.4 outputs.tf**

```hcl
output "ec2_public_ip" {
  description = "Публичный IP-адрес EC2-инстанса"
  value       = aws_instance.web.public_ip
}

output "s3_bucket_name" {
  description = "Имя S3-бакета"
  value       = aws_s3_bucket.files.bucket
}
```

# 3. Создание backend для состояния Terraform

По заданию требуется хранить `terraform.tfstate` в S3.

Через AWS Console вручную создан бакет:

```
my-tf-state-simple-k18
```

Внутри Terraform создаст файл:

```
aws_simple_lab/terraform.tfstate
```

# 4. Развёртывание инфраструктуры

### Инициализация Terraform:

```bash
terraform init
```

![image](https://i.imgur.com/xq2BjfK.png)

Успешно настроен backend и установлен AWS provider.

### Проверка плана:

```bash
terraform plan
```

![image](https://i.imgur.com/mdVIEoD.png)

Terraform планирует создать:

* EC2-инстанс `aws_instance.web`
* S3-бакет `aws_s3_bucket.files`

Plan:

```
Plan: 2 to add, 0 to change, 0 to destroy.
```

### Применение:

```bash
terraform apply
```

![image](https://i.imgur.com/XnFkRP4.png)

![image](https://i.imgur.com/I35PAnf.png)

![image](https://i.imgur.com/bifirkC.png)

После развёртывания Terraform вывел Outputs:

* публичный IP EC2
* имя S3-бакета

# 5. Проверка ресурсов в AWS Console

## **5.1 EC2**

В разделе *EC2 → Instances* создан инстанс:

* Name: `WebServer-dev`
* Type: `t3.micro`
* AMI: Amazon Linux 2
* Public IPv4: отображается в Outputs

![image](https://i.imgur.com/4PsjbtF.png)

## **5.2 Рабочий S3-бакет**

Бакет:
`my-simple-bucket-dev-k18`

В Permissions:

* **Block all public access: ON**
* Бакет приватный (требование выполнено)

![image](https://i.imgur.com/b9AcsaF.png)

![image](https://i.imgur.com/ZNCnvqd.png)

# 6. Получение выходных данных

```bash
terraform output
```

![image](https://i.imgur.com/M29ZEN9.png)


Это подтверждает корректную работу блока outputs.

# 7. Удаление инфраструктуры

После проверки ресурсов выполнена очистка:

```bash
terraform destroy
```

![image](https://i.imgur.com/GwgZiqm.png)

EC2-инстанс и рабочий S3-бакет были удалены.

![image](https://i.imgur.com/GOnnDZv.png)

![image](https://i.imgur.com/78pfMzn.png)

---

# 8. Выводы

В ходе лабораторной работы выполнено:

* настройка Terraform для AWS;
* развёртывание EC2-инстанса Amazon Linux 2;
* создание приватного S3-бакета;
* параметризация проекта через переменные:

  * `aws_region`
  * `env`
* настройка и использование **удалённого backend-а в S3**;
* генерация выходных данных (`outputs.tf`);
* проверка созданных ресурсов в AWS Console;
* очистка инфраструктуры командой `terraform destroy`.

Лабораторная работа полностью выполнена согласно заданию.