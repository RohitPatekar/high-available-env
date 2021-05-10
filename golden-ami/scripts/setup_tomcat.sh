#!/bin/bash
sudo yum install tomcat -y 
sudo yum install tomcat-webapps tomcat-admin-webapps tomcat-docs-webapp tomcat-javadoc -y
sudo yum install amazon-cloudwatch-agent -y
sudo yum install mysql -y
sudo aws s3 cp s3://webapp-distribution/Inventory.war /usr/share/tomcat/webapps/
sudo systemctl enable tomcat