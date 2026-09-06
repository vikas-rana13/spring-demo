pipeline {
    agent any

    // 1. Tell Jenkins to use your globally configured Maven and JDK 25 installations
    tools {
        maven 'jenkins-maven'  // Map your Maven installation name
        jdk 'jenkins-jdk-25'   // Map your JDK 25 installation name in Jenkins Tools
    }

    // 2. Separated Build and Test interactive parameter blocks
    parameters {
        booleanParam(name: 'BUILD', defaultValue: true, description: 'Compile the Java source code and package JAR?')
        booleanParam(name: 'TEST', defaultValue: true, description: 'Run Maven unit and integration tests?')
        booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Provision AWS stack and deploy Java Application?')
        string(name: 'APP_NAME', defaultValue: 'spring-boot-backend', description: 'Unique name for your application and AWS stack')
    }

    environment {
        AWS_REGION = 'ap-southeast-2'
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    stages {
        // 3. SEPARATED BUILD STAGE: Packages your application, bypassing the test suite
        stage('Compile & Package') {
            when { expression { params.BUILD } }
            steps {
                echo "=== Compiling Java 25 source code and generating executable JAR ==="
                sh "mvn clean package -DskipTests" 
            }
        }

        // 4. SEPARATED TEST STAGE: Runs unit tests independently
        stage('Execute Unit Tests') {
            when { expression { params.TEST } }
            steps {
                echo "=== Running Java Unit Tests ==="
                sh "mvn test"
            }
        }

        // 5. Provision AWS Infrastructure using CloudFormation
        stage('AWS CloudFormation Provisioning') {
            when { expression { params.DEPLOY } }
            steps {
                echo "=== Deploying/Updating AWS Infrastructure Stack: ${params.APP_NAME}-stack ==="
                sh """
                aws cloudformation deploy \
                  --stack-name "${params.APP_NAME}-stack" \
                  --template-file cloudformation/ec2-provision.yaml \
                  --parameter-overrides AppName="${params.APP_NAME}" KeyName="ec2-key" \
                  --capabilities CAPABILITY_IAM \
                  --region ${env.AWS_REGION}
                """
            }
        }

        // 6. Securely deploy the backend JAR and manage the background service
        stage('Deploy Backend to EC2') {
            when { expression { params.DEPLOY } }
            steps {
                echo "=== Fetching Public IP for Stack: ${params.APP_NAME}-stack ==="
                script {
                    def ec2Ip = sh(
                        script: "aws cloudformation describe-stacks --stack-name \"${params.APP_NAME}-stack\" --query \"Stacks[0].Outputs[?OutputKey=='EC2PublicIP'].OutputValue\" --output text --region ${env.AWS_REGION}",
                        returnStdout: true
                    ).trim()
                    
                    echo "Target EC2 Public IP: ${ec2Ip}"
                    
                    if (ec2Ip == "None" || ec2Ip == "") {
                        error "Deployment aborted: Could not retrieve a valid Public IP from CloudFormation output."
                    }
                    
                    echo "=== Transferring Jar and Launching App ==="
                    withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY')]) {
                        
                        // Step A: Securely copy the freshly compiled JAR file to the app directory
                        sh "scp -o StrictHostKeyChecking=no -i \$SSH_KEY target/*.jar ec2-user@${ec2Ip}:/home/ec2-user/app/app.jar"
                        
                        // Step B: SSH into the server, kill the previously running Spring Boot app (if any), 
                        // and start the new JAR running in the background.
                        sh """
                        ssh -o StrictHostKeyChecking=no -i \$SSH_KEY ec2-user@${ec2Ip} '
                            echo "=== Managing Service Processes ==="
                            # Find and gracefully terminate any running Java app processes
                            pgrep -f app.jar && kill -15 \$(pgrep -f app.jar) || echo "No active Java service detected."
                            
                            # Start Spring Boot app in background (nohup keeps it running after SSH session disconnects)
                            nohup java -jar /home/ec2-user/app/app.jar > /home/ec2-user/app/app.log 2>&1 &
                            
                            echo "=== Spring Boot (Java 25) Booted in Background! ==="
                        '
                        """
                    }
                }
                echo "=== Deployment Completed Successfully! ==="
            }
        }
    }
}
