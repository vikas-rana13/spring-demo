pipeline {
    agent any

    tools {
        maven 'jenkins-maven'
        jdk 'jenkins-jdk-25'
    }

    parameters {
        booleanParam(name: 'BUILD', defaultValue: true, description: 'Compile the Java source code and package JAR?')
        booleanParam(name: 'TEST', defaultValue: true, description: 'Run Maven unit and integration tests?')
        booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Provision AWS stack and deploy Java Application?')
        string(name: 'APP_NAME', defaultValue: 'spring-boot-backend', description: 'Unique name for your application and AWS stack')
    }

    // Centralized variable orchestration
    environment {
        AWS_REGION      = 'ap-southeast-2'
        APP_PORT        = '8081'                  // Target App Execution Port
        APP_USER        = 'ec2-user'              // Target Linux Deployment OS User
        APP_DIR         = '/home/ec2-user/app'    // Deploy Target directory
        JAR_NAME        = 'app.jar'               // Unified server-side executable name
        JAVA_VERSION    = '25'                    // Targeted platform Java execution environment
        PATH            = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    stages {
        stage('Compile & Package') {
            when { expression { params.BUILD } }
            steps {
                echo "=== Compiling Java ${env.JAVA_VERSION} codebase ==="
                sh "mvn clean package -DskipTests" 
            }
        }

        stage('Execute Unit Tests') {
            when { expression { params.TEST } }
            steps {
                echo "=== Running Java Unit Tests ==="
                sh "mvn test"
            }
        }

        stage('AWS CloudFormation Provisioning') {
            when { expression { params.DEPLOY } }
            steps {
                echo "=== Deploying/Updating AWS Infrastructure Stack ==="
                // Dynamic CFN Parameter Override mapping to our ENV block variable
                sh """
                aws cloudformation deploy \
                  --stack-name "${params.APP_NAME}-stack" \
                  --template-file cloudformation/ec2-provision.yaml \
                  --parameter-overrides AppName="${params.APP_NAME}" KeyName="ec2-key" AppPort="${env.APP_PORT}" \
                  --capabilities CAPABILITY_IAM \
                  --region ${env.AWS_REGION}
                """
            }
        }

        stage('Deploy Backend to EC2') {
            when { expression { params.DEPLOY } }
            steps {
                script {
                    def ec2Ip = sh(
                        script: "aws cloudformation describe-stacks --stack-name \"${params.APP_NAME}-stack\" --query \"Stacks[0].Outputs[?OutputKey=='EC2PublicIP'].OutputValue\" --output text --region ${env.AWS_REGION}",
                        returnStdout: true
                    ).trim()
                    
                    echo "Target EC2 Public IP: ${ec2Ip}"
                    
                    if (ec2Ip == "None" || ec2Ip == "") {
                        error "Deployment aborted: Could not retrieve a valid Public IP."
                    }
                    
                    withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY')]) {
                        echo "=== Transferring JAR and Standalone Scripts to EC2 ==="
                        sh "scp -o StrictHostKeyChecking=no -i \$SSH_KEY target/*.jar ${env.APP_USER}@${ec2Ip}:${env.APP_DIR}/${env.JAR_NAME}"
                        sh "scp -o StrictHostKeyChecking=no -i \$SSH_KEY scripts/pre.sh ${env.APP_USER}@${ec2Ip}:${env.APP_DIR}/pre.sh"
                        sh "scp -o StrictHostKeyChecking=no -i \$SSH_KEY scripts/start-service.sh ${env.APP_USER}@${ec2Ip}:${env.APP_DIR}/start-service.sh"
                        
                        echo "=== Running Environmental Pre-requisites ==="
                        // Injecting local Jenkins variables into SSH environment so script reads them dynamically
                        sh """
                        ssh -o StrictHostKeyChecking=no -i \$SSH_KEY ${env.APP_USER}@${ec2Ip} '
                            export JAVA_VERSION="${env.JAVA_VERSION}"
                            export APP_USER="${env.APP_USER}"
                            export APP_DIR="${env.APP_DIR}"
                            
                            chmod +x ${env.APP_DIR}/pre.sh
                            ${env.APP_DIR}/pre.sh
                        '
                        """
                        
                        echo "=== Booting Service Daemon ==="
                        sh """
                        ssh -o StrictHostKeyChecking=no -i \$SSH_KEY ${env.APP_USER}@${ec2Ip} '
                            export APP_PORT="${env.APP_PORT}"
                            export APP_DIR="${env.APP_DIR}"
                            export JAR_NAME="${env.JAR_NAME}"
                            
                            chmod +x ${env.APP_DIR}/start-service.sh
                            ${env.APP_DIR}/start-service.sh
                        '
                        """
                    }
                }
                echo "=== Deployment Completed Successfully! ==="
            }
        }
    }
}
