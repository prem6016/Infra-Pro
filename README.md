Project Title: Automated Developer VM Provisioning for Royal Hotel
Tools Used: Terraform, Ansible, Jenkins, AWS, SSH

1. Project Overview

Royal Hotel aims to automate the creation and management of developer virtual machines as part of their global scaling initiative. To achieve this, we designed a fully automated infrastructure provisioning pipeline using:

Terraform → Infrastructure as Code

AWS EC2 → Fully managed virtual machines

Ansible → Configuration management

Jenkins → Automated CI/CD triggering

SSH Key-Based Access → Secure VM login

This system allows the hotel’s engineering team to provision fresh developer sandboxes on-demand directly from a Jenkins job.

2. Objectives

The solution automates the following:

Configure Terraform with custom SSH key pair

Configure AWS CLI for remote provisioning

Provision a complete sandbox environment

Create and configure AWS VPC, Subnet, IGW, Route Table, Security Group, Key Pair

Deploy a developer VM (EC2)

Invoke Ansible automatically from Terraform for machine configuration

Trigger provisioning from Jenkins via a parameterized pipeline