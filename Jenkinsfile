def stage_results = [:]

pipeline {
    agent any 

    environment {
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
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
                    sh "docker stop test-db-${env.BUILD_NUMBER} || true"
                    sh "docker rm test-db-${env.BUILD_NUMBER} || true"
                    sh "docker network rm test-net-${env.BUILD_NUMBER} || true"

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
                
                # clean up old containers and network
                docker stop odin-app-live || true
                docker rm odin-app-live || true
                docker stop odin-db-live || true
                docker rm odin-db-live || true
                docker network rm odin-prod-net || true

                # create isolated network
                docker network create odin-prod-net

                # start database container
                export \$(grep -v '^#' .env | xargs)
                docker run -d \\
                  --name odin-db-live \\
                  --network odin-prod-net \\
                  -e POSTGRES_USER=\$POSTGRES_USERNAME \\
                  -e POSTGRES_PASSWORD=\$POSTGRES_PASSWORD \\
                  postgres:14

                # wait for database to boot
                sleep 5

                # start rails application container
                docker run -d \\
                  --name odin-app-live \\
                  --network odin-prod-net \\
                  -p 3000:3000 \\
                  -e RAILS_ENV=production \\
                  -e SECRET_KEY_BASE=\${SECRET_KEY_BASE:-dummy_secret_key_for_pipeline_run_32_chars_long} \\
                  -e DATABASE_URL=postgresql://\$POSTGRES_USERNAME:\$POSTGRES_PASSWORD@odin-db-live:5432/odin_production \\
                  odin-app:${env.BUILD_NUMBER} \\
                  sh -c "bundle exec rails db:prepare && bin/rails server -b 0.0.0.0"
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
                echo 'nothing yet'
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
                echo 'nothing yet'
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
                def ordered_stages = [
                    'Build', 'Test', 'Code Quality', 'Security',
                    'Deploy', 'Release', 'Monitoring'
                ]
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