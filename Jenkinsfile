def stage_results = [:]

pipeline {
    agent any 

    environment {
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
        DOCKER_HUB_USER = "hassanjamali"
        EC2_PUBLIC_IP = "15.135.220.57"
    }

    stages {
        stage('Build') {
            steps {
                // create the .env file by copying our secret file credentials
                withCredentials([file(credentialsId: 'odin-env', variable: 'source_env')]) {
                    // delete the old file before copying a new one
                    sh 'rm -f .env && cp $source_env .env'
                }
                // create our docker artifact tagged with the build number
                sh "docker build -t odin-app:${env.BUILD_NUMBER} ."
            }
            post {
                success {
                    script {
                        stage_results['Build'] = 'Passed'
                    }
                }
                failure {
                    script {
                        stage_results['Build'] = 'Failed'
                    }
                }
            }
        }
        stage('Test') {
            steps {
                sh """#!/bin/bash
                set -e 
                # load env variables
                export \$(grep -v '^#' .env | xargs)
                docker network create test-net-${env.BUILD_NUMBER}
                docker run -d \\
                  --name test-db-${env.BUILD_NUMBER} \\
                  --network test-net-${env.BUILD_NUMBER} \\
                  -e POSTGRES_USER=\$POSTGRES_USERNAME \\
                  -e POSTGRES_PASSWORD=\$POSTGRES_PASSWORD \\
                  postgres:14
                # wait for db to start
                sleep 5
                mkdir -p ${WORKSPACE}/test-results
                # run tests with db connection
                docker run --rm \\
                  --network test-net-${env.BUILD_NUMBER} \\
                  -e RAILS_ENV=test \\
                  -e DATABASE_URL=postgresql://\$POSTGRES_USERNAME:\$POSTGRES_PASSWORD@test-db-${env.BUILD_NUMBER}:5432/odin_test \\
                  -v ${WORKSPACE}/test-results:/app/test-results \\
                  odin-app:${env.BUILD_NUMBER} \\
                  sh -c "bundle exec rails db:drop db:create db:schema:load && bin/rspec --tag ~type:system --format documentation --format RspecJunitFormatter --out test-results/rspec.xml"
                """
            }
            post {
                always {
                    // clean up the database and network
                    sh "docker stop test-db-${env.BUILD_NUMBER} 2>/dev/null || true"
                    sh "docker rm test-db-${env.BUILD_NUMBER} 2>/dev/null || true"
                    sh "docker network rm test-net-${env.BUILD_NUMBER} 2>/dev/null || true"

                    junit 'test-results/rspec.xml'
                }
                success {
                    script {
                        stage_results['Test'] = 'Passed'
                    }
                }
                failure {
                    script {
                        stage_results['Test'] = 'Failed'
                    }
                }
            }
        }
        stage('Code Quality') {
            steps {
                // create a folder on Jenkins for the code quality reports
                sh "mkdir -p ${WORKSPACE}/quality_reports"
                // run rubocop, output a visual html report, and print standard progress to terminal
                sh """
                docker run --rm \\
                  -v ${WORKSPACE}/quality_reports:/app/quality_reports \\
                  odin-app:${env.BUILD_NUMBER} \\
                  sh -c "bundle exec rubocop --format markdown -o quality_reports/rubocop.md --format progress"
                """
            }
            post {
                always {
                    // save the code quality report to the jenkins dashboard
                    archiveArtifacts artifacts: 'quality_reports/rubocop.md', allowEmptyArchive: true
                }
                success {
                    script {
                        stage_results['Code Quality'] = 'Passed'
                    }
                }
                failure {
                    script {
                        stage_results['Code Quality'] = 'Failed'
                    }
                }
            }
        }
        stage('Security') {
            steps {
                // create folder for the security report
                sh "mkdir -p ${WORKSPACE}/security_reports"
                // run brakeman and output an html report
                sh """
                docker run --rm \\
                  -v ${WORKSPACE}/security_reports:/app/security_reports \\
                  odin-app:${env.BUILD_NUMBER} \\
                  sh -c "bundle exec brakeman -o security_reports/brakeman.md -o -"
                """
            }
            post {
                always {
                    // save the security report to the jenkins dashboard
                    archiveArtifacts artifacts: 'security_reports/brakeman.md', allowEmptyArchive: true
                }
                success {
                    script {
                        stage_results['Security'] = 'Passed'
                    }
                }
                failure {
                    script {
                        stage_results['Security'] = 'Failed'
                    }
                }
            }
        }
        stage('Deploy') {
            steps {
            sh """#!/bin/bash
            set -e
            echo "deploying to staging environment using docker-compose..."
            # export variables needed by docker-compose
            export \$(grep -v '^#' .env | xargs)
            export BUILD_NUMBER=${env.BUILD_NUMBER}
            # start the staging environment
            docker compose -f docker-compose.staging.yml up -d
            # perform health check on staging
            sleep 30
            if curl -f http://localhost:3001/ > /dev/null 2>&1; then
                echo "staging health check passed."
            else
                echo "staging health check failed. rollback previous version"
                docker compose -f docker-compose.staging.yml down
                exit 1
            fi
            """
            }
            post {
                success {
                    script {
                        stage_results['Deploy'] = 'Passed'
                    }
                }
                failure {
                    script {
                        stage_results['Deploy'] = 'Failed'
                    }
                }
            }
        }
        stage('Release') {
            steps {
                // push tagged image to docker hub
                withCredentials([usernamePassword(credentialsId: 'docker-hub-credentials', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                    sh """#!/bin/bash
                    set -e
                    echo "\$DH_PASS" | docker login -u "\$DH_USER" --password-stdin
                    docker tag odin-app:${env.BUILD_NUMBER} ${env.DOCKER_HUB_USER}/odin-app:${env.BUILD_NUMBER}
                    docker tag odin-app:${env.BUILD_NUMBER} ${env.DOCKER_HUB_USER}/odin-app:latest
                    docker push ${env.DOCKER_HUB_USER}/odin-app:${env.BUILD_NUMBER}
                    docker push ${env.DOCKER_HUB_USER}/odin-app:latest
                    """
                }
                // trigger AWS CodeDeploy and wait for completion
                withCredentials([usernamePassword(credentialsId: 'aws-credentials', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh """#!/bin/bash
                    set -e
                    export AWS_DEFAULT_REGION="ap-southeast-2"
                    DEPLOYMENT_ID=\$(aws deploy create-deployment \\
                        --application-name OdinApp \\
                        --deployment-group-name OdinAppProdGroup \\
                        --github-location repository=hassan-jamali/theodinproject,commitId=\$(git rev-parse HEAD) \\
                        --query "deploymentId" --output text)
                    echo "Waiting for CodeDeploy deployment to complete"
                    aws deploy wait deployment-successful --deployment-id "\$DEPLOYMENT_ID"
                    """
            }
        }
            post {
                success {
                    script {
                        stage_results['Release'] = 'Passed'
                    }
                }
                failure {
                    script {
                        stage_results['Release'] = 'Failed'
                    }
                }
            }
        }
        stage('Monitoring') {
            steps {
                script {
                    echo "Datadog Agent is monitoring the EC2 instance and the Docker containers."
                    echo "Alert rules are configured in the Datadog dashboard."
                }
            }
            post {
                success {
                    script {
                        stage_results['Monitoring'] = 'Passed'
                    }
                }
                failure {
                    script {
                        stage_results['Monitoring'] = 'Failed'
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                println "Final Results: ${stage_results}"
            }
        }
        success {
            echo "The Pipeline was successfully!"
        }
        failure {
            echo "The Pipeline was unsuccessful!"
        }
    }
}