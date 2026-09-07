pipeline {
    agent any

    tools {
        maven 'jenkins-maven'
        jdk 'jenkins-jdk-25'
    }

    // 🌟 ENTERPRISE PARAMETERS FOR SHAPING RUN MODES
    parameters {
        booleanParam(name: 'BUILD', defaultValue: true, description: 'Compile the Java source code and package JAR?')
        booleanParam(name: 'TEST', defaultValue: true, description: 'Run Maven unit and integration tests?')
        booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Provision AWS stack and deploy Java Application?')
        string(name: 'APP_NAME', defaultValue: 'spring-boot-backend', description: 'Unique name for your application and AWS stack')
        
        // 🚀 DYNAMIC ARTIFACT TARGETING: Allows immediate rollback or redeployment of any past image tag
        string(name: 'DEPLOY_TAG', defaultValue: '', description: 'Leave blank to build and deploy current commit. Enter a previous build number (e.g., 14) to deploy that specific pre-existing image.')
    }

    environment {
        AWS_REGION                = 'ap-southeast-2'
        PORT                      = '8081'                  // Port the container maps to the outside world
        APP_USER                  = 'ec2-user'              // OS user on the target EC2 machine
        APP_DIR                   = '/home/ec2-user/app'    // Host path to drop deployment scripts
        DOCKER_HUB_CREDENTIALS_ID = 'docker-hub-credentials' // Jenkins credentials ID for Docker Hub
        PATH                      = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    stages {
        stage('Detect Metadata & Package') {
            when { expression { params.BUILD } }
            steps {
                script {
                    echo "=== Reading Single Source of Truth from pom.xml ==="
                    // Extract Java version target dynamically from pom.xml
                    env.JAVA_VERSION = sh(
                        script: "mvn help:evaluate -Dexpression=java.version -q -DforceStdout",
                        returnStdout: true
                    ).trim()
                    echo "Detected Target Java Version: ${env.JAVA_VERSION}"
                }
                echo "=== Compiling and Packaging Spring Boot app ==="
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
                echo "=== Standardizing Server Infrastructure: ${params.APP_NAME}-stack ==="
                // Provisions a clean EC2 host without complex ECR roles
                sh """
                aws cloudformation deploy \
                  --stack-name "${params.APP_NAME}-stack" \
                  --template-file cloudformation/ec2-provision.yaml \
                  --parameter-overrides AppName="${params.APP_NAME}" KeyName="ec2-key" AppPort="${env.PORT}" \
                  --capabilities CAPABILITY_IAM \
                  --region ${env.AWS_REGION}
                """
            }
        }

        stage('Determine Deployment Tag') {
            when { expression { params.DEPLOY } }
            steps {
                script {
                    // Resolve which artifact version tag to use.
                    // If DEPLOY_TAG is left blank, use the current build number.
                    // If DEPLOY_TAG is populated, use the targeted past build number.
                    env.IMAGE_TAG = params.DEPLOY_TAG.trim() ? params.DEPLOY_TAG.trim() : env.BUILD_NUMBER
                    echo "Targeting Artifact Version Tag for Deployment: Build #${env.IMAGE_TAG}"
                }
            }
        }

        stage('Build & Push Docker Image') {
            // Only run this stage if deploying AND building a brand new code compile.
            // If deploying a pre-existing artifact, this stage is safely bypassed.
            when {
                allOf {
                    expression { params.DEPLOY }
                    expression { params.BUILD }
                }
            }
            steps {
                script {
                    env.IMAGE_NAME = params.APP_NAME
                    
                    // Securely load Docker Hub credentials from the Jenkins Credentials Store
                    withCredentials([usernamePassword(credentialsId: env.DOCKER_HUB_CREDENTIALS_ID, usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        
                        echo "=== Building Docker Image Locally ==="
                        sh "docker build -t ${DOCKER_USER}/${env.IMAGE_NAME}:${env.IMAGE_TAG} ."

                        echo "=== Authenticating Jenkins Controller against Docker Hub ==="
                        sh "echo \$DOCKER_PASS | docker login --username \$DOCKER_USER --password-stdin"

                        echo "=== Pushing Image to Docker Hub ==="
                        sh "docker push ${DOCKER_USER}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                    }
                }
            }
        }

        stage('Deploy Backend to EC2') {
            when { expression { params.DEPLOY } }
            steps {
                script {
                    // Fetch the target EC2 Public IP from CloudFormation output dynamically
                    def ec2Ip = sh(
                        script: "aws cloudformation describe-stacks --stack-name \"${params.APP_NAME}-stack\" --query \"Stacks.Outputs[?OutputKey=='EC2PublicIP'].OutputValue\" --output text --region ${env.AWS_REGION}",
                        returnStdout: true
                    ).trim()
                    
                    echo "Target EC2 Public IP: ${ec2Ip}"
                    
                    if (ec2Ip == "None" || ec2Ip == "") {
                        error "Deployment aborted: Could not retrieve a valid Public IP."
                    }
                    
                    // Pull credentials from Jenkins to connect via SSH and log into Docker Hub on the host
                    withCredentials([
                        sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY'),
                        usernamePassword(credentialsId: env.DOCKER_HUB_CREDENTIALS_ID, usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')
                    ]) {
                        echo "=== Transferring Standard Setup and Run Scripts ==="
                        sh "scp -o StrictHostKeyChecking=no -i \$SSH_KEY scripts/pre.sh ${env.APP_USER}@${ec2Ip}:${env.APP_DIR}/pre.sh"
                        sh "scp -o StrictHostKeyChecking=no -i \$SSH_KEY scripts/start-service.sh ${env.APP_USER}@${ec2Ip}:${env.APP_DIR}/start-service.sh"
                        
                        echo "=== Initializing Docker on EC2 (Runs once) ==="
                        sh """
                        ssh -o StrictHostKeyChecking=no -i \$SSH_KEY ${env.APP_USER}@${ec2Ip} '
                            chmod +x ${env.APP_DIR}/pre.sh
                            ${env.APP_DIR}/pre.sh
                        '
                        """
                        
                        echo "=== Launching Containerized Version: Build #${env.IMAGE_TAG} ==="
                        sh """
                        ssh -o StrictHostKeyChecking=no -i \$SSH_KEY ${env.APP_USER}@${ec2Ip} '
                            export DOCKER_USER="${DOCKER_USER}"
                            export DOCKER_PASSWORD="${DOCKER_PASS}"
                            export IMAGE_NAME="${params.APP_NAME}"
                            export IMAGE_TAG="${env.IMAGE_TAG}"
                            export APP_PORT="${env.PORT}"
                            export APP_DIR="${env.APP_DIR}"
                            
                            chmod +x ${env.APP_DIR}/start-service.sh
                            ${env.APP_DIR}/start-service.sh
                        '
                        """
                    }
                }
                echo "=== Cloud-Native Container Deployment Completed Successfully! === "
            }
        }
    }
}
