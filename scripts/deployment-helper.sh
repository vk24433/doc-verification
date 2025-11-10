#!/bin/bash
#
# Airflow Deployment Helper Script
# Usage: ./deployment-helper.sh [command] [options]
#

set -e

NEXUS_REGISTRY="${NEXUS_REGISTRY:-nexus.yourcompany.com:8443}"
IMAGE_NAME="${IMAGE_NAME:-airflow-custom}"
SERVER_130="dataeng99@172.10.17.130"
SERVER_131="dataeng99@172.10.17.131"
SSH_PORT="3535"
SSH_KEY="/home/dataeng99/.ssh/dataeng99_id_rsa"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

function print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

function print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

function print_error() {
    echo -e "${RED}❌ $1${NC}"
}

function show_help() {
    cat << EOF
Airflow Deployment Helper Script

Usage: $0 [command] [options]

Commands:
    list-versions [server]      List all available image versions on a server
                                server: 130 or 131 (optional, shows both if omitted)
    
    current-version [server]    Show currently deployed version on a server
                                server: 130 or 131 (optional, shows both if omitted)
    
    rollback [server] [tag]     Rollback to a specific version
                                server: 130, 131, or 'both'
                                tag: image tag to rollback to
    
    health-check [server]       Check health of Airflow services
                                server: 130, 131, or 'both'
    
    cleanup [server]            Clean up old unused Docker images
                                server: 130, 131, or 'both'
    
    logs [server] [service]     Show logs for a service
                                server: 130 or 131
                                service: webserver, scheduler, mysql, etc.

Examples:
    $0 list-versions 130
    $0 current-version both
    $0 rollback 130 abc123def
    $0 health-check both
    $0 logs 130 webserver

EOF
}

function ssh_command() {
    local server=$1
    local command=$2
    ssh -p${SSH_PORT} -i ${SSH_KEY} ${server} "${command}"
}

function list_versions() {
    local server=$1
    
    if [[ "$server" == "130" || -z "$server" ]]; then
        print_info "Fetching available versions from Server 130..."
        ssh_command ${SERVER_130} "sudo -u developer docker images ${NEXUS_REGISTRY}/${IMAGE_NAME} --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}'"
        echo ""
    fi
    
    if [[ "$server" == "131" || -z "$server" ]]; then
        print_info "Fetching available versions from Server 131..."
        ssh_command ${SERVER_131} "sudo -u developer docker images ${NEXUS_REGISTRY}/${IMAGE_NAME} --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}'"
    fi
}

function current_version() {
    local server=$1
    
    if [[ "$server" == "130" || -z "$server" ]]; then
        print_info "Current deployment on Server 130:"
        ssh_command ${SERVER_130} "sudo -u developer cat /data/airflow-deployments/current-deployment-130.json 2>/dev/null || echo 'No deployment metadata found'" | jq . 2>/dev/null || cat
        echo ""
    fi
    
    if [[ "$server" == "131" || -z "$server" ]]; then
        print_info "Current deployment on Server 131:"
        ssh_command ${SERVER_131} "sudo -u developer cat /data/airflow-deployments/current-deployment-131.json 2>/dev/null || echo 'No deployment metadata found'" | jq . 2>/dev/null || cat
    fi
}

function rollback() {
    local server=$1
    local tag=$2
    
    if [[ -z "$tag" ]]; then
        print_error "Image tag is required for rollback!"
        echo "Usage: $0 rollback [server] [tag]"
        exit 1
    fi
    
    local rollback_image="${NEXUS_REGISTRY}/${IMAGE_NAME}:${tag}"
    
    print_warning "Rolling back to: ${rollback_image}"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_info "Rollback cancelled"
        exit 0
    fi
    
    if [[ "$server" == "130" || "$server" == "both" ]]; then
        print_info "Rolling back Server 130..."
        ssh_command ${SERVER_130} "
            echo '${NEXUS_PASSWORD}' | sudo -u developer docker login ${NEXUS_REGISTRY} -u ${NEXUS_USERNAME} --password-stdin &&
            sudo -u developer docker pull ${rollback_image} &&
            sudo -u developer sed -i 's|image:.*airflow.*|image: ${rollback_image}|g' /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker/docker-compose-server-130.yaml &&
            sudo -u developer /data/binaries/docker-compose -f /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker/docker-compose-server-130.yaml up -d
        "
        print_success "Server 130 rolled back successfully"
    fi
    
    if [[ "$server" == "131" || "$server" == "both" ]]; then
        print_info "Rolling back Server 131..."
        ssh_command ${SERVER_131} "
            echo '${NEXUS_PASSWORD}' | sudo -u developer docker login ${NEXUS_REGISTRY} -u ${NEXUS_USERNAME} --password-stdin &&
            sudo -u developer docker pull ${rollback_image} &&
            sudo -u developer sed -i 's|image:.*airflow.*|image: ${rollback_image}|g' /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker/docker-compose-server-131.yaml &&
            sudo -u developer /data/binaries/docker-compose -f /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker/docker-compose-server-131.yaml up -d
        "
        print_success "Server 131 rolled back successfully"
    fi
}

function health_check() {
    local server=$1
    
    if [[ "$server" == "130" || "$server" == "both" || -z "$server" ]]; then
        print_info "Health check for Server 130..."
        ssh_command ${SERVER_130} "
            sudo -u developer docker ps --filter 'name=airflow' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
        "
        echo ""
    fi
    
    if [[ "$server" == "131" || "$server" == "both" || -z "$server" ]]; then
        print_info "Health check for Server 131..."
        ssh_command ${SERVER_131} "
            sudo -u developer docker ps --filter 'name=airflow' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
        "
    fi
}

function cleanup() {
    local server=$1
    local keep_count=5
    
    print_warning "This will remove old Docker images (keeping last ${keep_count} versions)"
    read -p "Continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
    
    if [[ "$server" == "130" || "$server" == "both" ]]; then
        print_info "Cleaning up Server 130..."
        ssh_command ${SERVER_130} "
            sudo -u developer docker images ${NEXUS_REGISTRY}/${IMAGE_NAME} --format '{{.Tag}} {{.ID}}' | grep -v latest | tail -n +$((${keep_count} + 1)) | awk '{print \$2}' | xargs -r sudo -u developer docker rmi -f || true
        "
        print_success "Server 130 cleanup completed"
    fi
    
    if [[ "$server" == "131" || "$server" == "both" ]]; then
        print_info "Cleaning up Server 131..."
        ssh_command ${SERVER_131} "
            sudo -u developer docker images ${NEXUS_REGISTRY}/${IMAGE_NAME} --format '{{.Tag}} {{.ID}}' | grep -v latest | tail -n +$((${keep_count} + 1)) | awk '{print \$2}' | xargs -r sudo -u developer docker rmi -f || true
        "
        print_success "Server 131 cleanup completed"
    fi
}

function show_logs() {
    local server=$1
    local service=$2
    
    if [[ -z "$service" ]]; then
        print_error "Service name is required!"
        echo "Usage: $0 logs [server] [service]"
        exit 1
    fi
    
    local compose_file=""
    if [[ "$server" == "130" ]]; then
        compose_file="/data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker/docker-compose-server-130.yaml"
        print_info "Showing logs for ${service} on Server 130..."
        ssh_command ${SERVER_130} "sudo -u developer /data/binaries/docker-compose -f ${compose_file} logs -f --tail=100 ${service}"
    elif [[ "$server" == "131" ]]; then
        compose_file="/data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker/docker-compose-server-131.yaml"
        print_info "Showing logs for ${service} on Server 131..."
        ssh_command ${SERVER_131} "sudo -u developer /data/binaries/docker-compose -f ${compose_file} logs -f --tail=100 ${service}"
    else
        print_error "Invalid server. Use 130 or 131"
        exit 1
    fi
}

# Main script logic
case "$1" in
    list-versions)
        list_versions "$2"
        ;;
    current-version)
        current_version "$2"
        ;;
    rollback)
        rollback "$2" "$3"
        ;;
    health-check)
        health_check "$2"
        ;;
    cleanup)
        cleanup "$2"
        ;;
    logs)
        show_logs "$2" "$3"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
