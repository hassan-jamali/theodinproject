def stage_results = [:]

pipeline {
    agent any 

    environment {
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
        DOCKER_HUB_USER = "hassanjamali"
        EC2_PUBLIC_IP = "3.27.32.216"
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
                echo "deploying to staging environment..."
                # record currently running staging image tag for rollback
                PREV_TAG=\$(docker inspect --format='{{.Config.Image}}' odin-staging-app 2>/dev/null || echo "")
                # create staging network
                docker network create odin-staging-net 2>/dev/null || true
                # start staging database
                export \$(grep -v '^#' .env | xargs)
                if [ ! "\$(docker ps -q -f name=odin-staging-db)" ]; then
                    docker run -d \\
                      --name odin-staging-db \\
                      --network odin-staging-net \\
                      -e POSTGRES_USER=\$POSTGRES_USERNAME \\
                      -e POSTGRES_PASSWORD=\$POSTGRES_PASSWORD \\
                      postgres:14
                    sleep 5
                fi
                # stop active staging container
                docker stop odin-staging-app 2>/dev/null || true
                docker rm odin-staging-app 2>/dev/null || true
                # start new container version
                docker run -d \\
                  --name odin-staging-app \\
                  --network odin-staging-net \\
                  -p 3001:3000 \\
                  -e RAILS_ENV=production \\
                  -e SECRET_KEY_BASE=\${SECRET_KEY_BASE:-dummy_secret_key_for_pipeline_run_32_chars_long} \\
                  -e DATABASE_URL=postgresql://\$POSTGRES_USERNAME:\$POSTGRES_PASSWORD@odin-staging-db:5432/odin_staging \\
                  odin-app:${env.BUILD_NUMBER} \\
                  sh -c "bundle exec rails db:prepare && bin/rails server -b 0.0.0.0"
                # perform health check on staging
                sleep 30
                if curl -f http://localhost:3001/ > /dev/null 2>&1; then
                    echo "staging health check passed."
                else
                    echo "staging health check failed! initiating rollback..."
                    docker stop odin-staging-app 2>/dev/null || true
                    docker rm odin-staging-app 2>/dev/null || true
                    if [ -n "\$PREV_TAG" ]; then
                        echo "rolling back to: \$PREV_TAG"
                        docker run -d \\
                          --name odin-staging-app \\
                          --network odin-staging-net \\
                          -p 3001:3000 \\
                          -e RAILS_ENV=production \\
                          -e SECRET_KEY_BASE=\${SECRET_KEY_BASE:-dummy_secret_key_for_pipeline_run_32_chars_long} \\
                          -e DATABASE_URL=postgresql://\$POSTGRES_USERNAME:\$POSTGRES_PASSWORD@odin-staging-db:5432/odin_staging \\
                          \$PREV_TAG \\
                          sh -c "bin/rails server -b 0.0.0.0"
                    else
                        echo "no previous image found to rollback to."
                    fi
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
                    # authenticate and push
                    echo "\$DH_PASS" | docker login -u "\$DH_USER" --password-stdin
                    docker tag odin-app:${env.BUILD_NUMBER} ${env.DOCKER_HUB_USER}/odin-app:${env.BUILD_NUMBER}
                    docker tag odin-app:${env.BUILD_NUMBER} ${env.DOCKER_HUB_USER}/odin-app:latest
                    docker push ${env.DOCKER_HUB_USER}/odin-app:${env.BUILD_NUMBER}
                    docker push ${env.DOCKER_HUB_USER}/odin-app:latest
                    """
                }
                // deploy to aws ec2 production environment
                sshagent(['ec2-ssh-key']) {
                    sh """#!/bin/bash
                    set -e
                    scp -o StrictHostKeyChecking=no .env ubuntu@${env.EC2_PUBLIC_IP}:/home/ubuntu/.env
                    ssh -o StrictHostKeyChecking=no ubuntu@${env.EC2_PUBLIC_IP} << 'EOF'
                    set -e
                    # pull newly released image
                    docker pull ${env.DOCKER_HUB_USER}/odin-app:${env.BUILD_NUMBER}
                    # ensure prod network and db exist
                    docker network create odin-prod-net 2>/dev/null || true
                    if [ ! "\$(docker ps -q -f name=odin-prod-db)" ]; then
                        docker run -d \\
                          --name odin-prod-db \\
                          --network odin-prod-net \\
                          -e POSTGRES_USER=postgres \\
                          -e POSTGRES_PASSWORD=productionpassword \\
                          postgres:14
                        sleep 5
                    fi
                    # stop active container
                    docker stop odin-prod-app 2>/dev/null || true
                    docker rm odin-prod-app 2>/dev/null || true
                    # start new production container
                    docker run -d \\
                      --name odin-prod-app \\
                      --network odin-prod-net \\
                      -p 3000:3000 \\
                      --env-file /home/ubuntu/.env \\
                      -e RAILS_ENV=production \\
                      -e SECRET_KEY_BASE=production_secret_key_base_32_characters_long_val \\
                      -e DATABASE_URL=postgresql://postgres:productionpassword@odin-prod-db:5432/odin_production \\
                      ${env.DOCKER_HUB_USER}/odin-app:${env.BUILD_NUMBER} \\
                      sh -c "bundle exec rails db:prepare && bin/rails server -b 0.0.0.0"
EOF
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
                sh """#!/bin/bash
                set -e
                # wait for the production rails server to fully boot
                echo "waiting for rails to start..."
                sleep 60
                echo "monitoring production service on aws ec2..."
                # perform live endpoint verification
                HTTP_STATUS=\$(curl -s -o /dev/null -w "%{http_code}" http://${env.EC2_PUBLIC_IP}:3000/ || true)
                echo "endpoint returned status: \$HTTP_STATUS"
                if [ "\$HTTP_STATUS" -eq 200 ] || [ "\$HTTP_STATUS" -eq 302 ]; then
                    echo "production health check successful (status \$HTTP_STATUS)"
                else
                    echo "alert: application health degraded (status \$HTTP_STATUS)"
                    exit 1
                fi
                """
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