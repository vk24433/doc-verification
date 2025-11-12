#!/bin/bash

##############################################################################
# Airflow Deployment Helper Script
# 
# This script provides manual deployment, health check, and rollback utilities
# for Airflow on servers 130 and 131.
#
# Usage:
#   ./deploy-helper.sh [command] [server]
#
# Commands:
#   build         - Build Docker image
#   deploy        - Deploy to specified server
#   health-check  - Check container health
#   rollback      - Rollback to previous stable image
#   cleanup       - Clean up old images
#   status        - Show current deployment status
#
# Servers:
#   131, 130, both
##############################################################################

set -euo pipefail

# Configuration
IMAGE_NAME="${IMAGE_NAME:-airflow-custom}"
SERVER_131_HOST="172.10.17.131"
SERVER_130_HOST="172.10.17.130"
SSH_PORT="3535"
SSH_USER="dataeng99"
SSH_KEY="/home/dataeng99/.ssh/dataeng99_id_rsa"
DEPLOY_USER="developer"
CODE_BASE_PATH="/data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow"
DOCKER_COMPOSE_BIN="/data/binaries/docker-compose"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

##############################################################################
# Health Check Function
##############################################################################
health_check() {
    local SERVER=$1
    local CONTAINERS=$2
    local MAX_RETRIES=${3:-5}
    local SLEEP_SECONDS=${4:-15}
    
    log_info "Performing health check on Server $SERVER..."
    
    local SSH_HOST
    if [ "$SERVER" = "131" ]; then
        SSH_HOST=$SERVER_131_HOST
    else
        SSH_HOST=$SERVER_130_HOST
    fi
    
    ssh -p${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SSH_HOST} bash << EOF
        MAX_RETRIES=$MAX_RETRIES
        SLEEP_SECONDS=$SLEEP_SECONDS
        
        for i in \$(seq 1 \$MAX_RETRIES); do
            echo "Check \$i of \$MAX_RETRIES..."
            
            # Check restart counts
            RESTARTS=\$(sudo -u ${DEPLOY_USER} docker ps -a $CONTAINERS -q 2>/dev/null | \
                xargs -I {} sudo -u ${DEPLOY_USER} docker inspect -f '{{.RestartCount}}' {} 2>/dev/null | \
                awk '{sum+=\$1} END {print sum+0}')
            
            # Check for unhealthy containers
            UNHEALTHY=\$(sudo -u ${DEPLOY_USER} docker ps $CONTAINERS --filter 'health=unhealthy' -q 2>/dev/null)
            
            # Check for exited/dead containers
            EXITED=\$(sudo -u ${DEPLOY_USER} docker ps -a $CONTAINERS \
                --filter 'status=exited' --filter 'status=dead' -q 2>/dev/null)
            
            # Count running containers
            RUNNING_COUNT=\$(sudo -u ${DEPLOY_USER} docker ps $CONTAINERS --filter 'status=running' -q 2>/dev/null | wc -l)
            
            echo "  Restart count: \$RESTARTS"
            echo "  Unhealthy containers: \$(echo \$UNHEALTHY | wc -w)"
            echo "  Exited containers: \$(echo \$EXITED | wc -w)"
            echo "  Running containers: \$RUNNING_COUNT"
            
            if [ "\$RESTARTS" -eq 0 ] && [ -z "\$UNHEALTHY" ] && [ -z "\$EXITED" ] && [ "\$RUNNING_COUNT" -gt 0 ]; then
                echo "✅ All containers stable and healthy"
                exit 0
            else
                echo "⚠️  Containers not ready yet, retrying in \$SLEEP_SECONDS seconds..."
                sleep \$SLEEP_SECONDS
            fi
            
            if [ "\$i" -eq "\$MAX_RETRIES" ]; then
                echo "❌ Health check failed after retries"
                exit 1
            fi
        done
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Health check passed on Server $SERVER"
        return 0
    else
        log_error "Health check failed on Server $SERVER"
        return 1
    fi
}

##############################################################################
# Build Image
##############################################################################
build_image() {
    local IMAGE_TAG=${1:-$(date +%Y%m%d-%H%M%S)}
    
    log_info "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}-temp"
    
    ssh -p${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SERVER_131_HOST} << EOF
        cd ${CODE_BASE_PATH}/docker
        
        sudo -u ${DEPLOY_USER} docker build \
            --build-arg BUILD_DATE="\$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
            --build-arg VCS_REF="\$(git rev-parse --short HEAD)" \
            --build-arg VERSION="${IMAGE_TAG}" \
            -t ${IMAGE_NAME}:${IMAGE_TAG}-temp \
            -t ${IMAGE_NAME}:latest-temp \
            -f Dockerfile .
        
        if [ \$? -eq 0 ]; then
            echo "✅ Image built successfully"
            sudo -u ${DEPLOY_USER} docker images | grep ${IMAGE_NAME}
        else
            echo "❌ Image build failed"
            exit 1
        fi
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Image built successfully"
        echo "$IMAGE_TAG"
    else
        log_error "Image build failed"
        exit 1
    fi
}

##############################################################################
# Deploy to Server
##############################################################################
deploy_server() {
    local SERVER=$1
    local IMAGE_TAG=$2
    
    local SSH_HOST
    local COMPOSE_FILE
    local CONTAINERS
    
    if [ "$SERVER" = "131" ]; then
        SSH_HOST=$SERVER_131_HOST
        COMPOSE_FILE="docker-compose-server-131.yaml"
        CONTAINERS="--filter 'name=airflow_2.11-mysql_8.0' --filter 'name=airflow_2.11-scheduler_2'"
    elif [ "$SERVER" = "130" ]; then
        SSH_HOST=$SERVER_130_HOST
        COMPOSE_FILE="docker-compose-server-130.yaml"
        CONTAINERS="--filter 'name=airflow_2.11-webserver' --filter 'name=airflow_2.11-scheduler_1'"
    else
        log_error "Invalid server: $SERVER"
        exit 1
    fi
    
    log_info "Deploying to Server $SERVER with image tag: $IMAGE_TAG"
    
    # If deploying to 130, first copy image from 131
    if [ "$SERVER" = "130" ]; then
        log_info "Copying image from Server 131 to 130..."
        ssh -p${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SERVER_131_HOST} \
            "sudo -u ${DEPLOY_USER} docker save ${IMAGE_NAME}:${IMAGE_TAG} | \
            ssh -p${SSH_PORT} ${SSH_USER}@${SERVER_130_HOST} \
            'sudo -u ${DEPLOY_USER} docker load'"
    fi
    
    ssh -p${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SSH_HOST} << EOF
        cd ${CODE_BASE_PATH}
        
        # Set environment variable for docker-compose
        export CUSTOM_IMAGE_TAG="${IMAGE_TAG}"
        export CUSTOM_IMAGE_NAME="${IMAGE_NAME}"
        
        # Stop existing containers
        log_info "Stopping existing containers..."
        sudo -u ${DEPLOY_USER} ${DOCKER_COMPOSE_BIN} -f docker/${COMPOSE_FILE} down
        
        # Start new containers
        log_info "Starting containers with new image..."
        sudo -u ${DEPLOY_USER} ${DOCKER_COMPOSE_BIN} -f docker/${COMPOSE_FILE} up -d
        
        # Wait for initialization
        echo "Waiting for containers to initialize (30s)..."
        sleep 30
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Containers started on Server $SERVER"
        
        # Perform health check
        if health_check "$SERVER" "$CONTAINERS"; then
            log_success "Deployment successful on Server $SERVER"
            return 0
        else
            log_error "Health check failed on Server $SERVER"
            return 1
        fi
    else
        log_error "Deployment failed on Server $SERVER"
        return 1
    fi
}

##############################################################################
# Rollback
##############################################################################
rollback_server() {
    local SERVER=$1
    
    local SSH_HOST
    local COMPOSE_FILE
    
    if [ "$SERVER" = "131" ]; then
        SSH_HOST=$SERVER_131_HOST
        COMPOSE_FILE="docker-compose-server-131.yaml"
    elif [ "$SERVER" = "130" ]; then
        SSH_HOST=$SERVER_130_HOST
        COMPOSE_FILE="docker-compose-server-130.yaml"
    else
        log_error "Invalid server: $SERVER"
        exit 1
    fi
    
    log_warning "Rolling back Server $SERVER to stable image..."
    
    ssh -p${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SSH_HOST} << EOF
        cd ${CODE_BASE_PATH}
        
        # Check for stable image
        STABLE_IMAGE=\$(sudo -u ${DEPLOY_USER} docker images | grep '${IMAGE_NAME}' | grep 'stable' | head -1 | awk '{print \$2}')
        
        if [ -n "\$STABLE_IMAGE" ]; then
            echo "Found stable image: ${IMAGE_NAME}:\$STABLE_IMAGE"
            
            export CUSTOM_IMAGE_TAG="\$STABLE_IMAGE"
            export CUSTOM_IMAGE_NAME="${IMAGE_NAME}"
            
            sudo -u ${DEPLOY_USER} ${DOCKER_COMPOSE_BIN} -f docker/${COMPOSE_FILE} down
            sudo -u ${DEPLOY_USER} ${DOCKER_COMPOSE_BIN} -f docker/${COMPOSE_FILE} up -d
            
            echo "✅ Rolled back to stable image"
        else
            echo "⚠️  No stable image found"
            exit 1
        fi
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Rollback completed on Server $SERVER"
    else
        log_error "Rollback failed on Server $SERVER"
        exit 1
    fi
}

##############################################################################
# Status Check
##############################################################################
show_status() {
    local SERVER=$1
    
    local SSH_HOST
    if [ "$SERVER" = "131" ]; then
        SSH_HOST=$SERVER_131_HOST
    elif [ "$SERVER" = "130" ]; then
        SSH_HOST=$SERVER_130_HOST
    else
        log_error "Invalid server: $SERVER"
        exit 1
    fi
    
    log_info "Status for Server $SERVER ($SSH_HOST):"
    
    ssh -p${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SSH_HOST} << EOF
        echo "=== Docker Images ==="
        sudo -u ${DEPLOY_USER} docker images | grep -E '${IMAGE_NAME}|REPOSITORY'
        
        echo ""
        echo "=== Running Containers ==="
        sudo -u ${DEPLOY_USER} docker ps --filter 'name=airflow' --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
        
        echo ""
        echo "=== Container Health ==="
        sudo -u ${DEPLOY_USER} docker ps --filter 'name=airflow' --format 'table {{.Names}}\t{{.Status}}' | grep -E 'healthy|unhealthy'
EOF
}

##############################################################################
# Cleanup Old Images
##############################################################################
cleanup_images() {
    local SERVER=$1
    local KEEP_COUNT=${2:-3}
    
    local SSH_HOST
    if [ "$SERVER" = "131" ]; then
        SSH_HOST=$SERVER_131_HOST
    elif [ "$SERVER" = "130" ]; then
        SSH_HOST=$SERVER_130_HOST
    else
        log_error "Invalid server: $SERVER"
        exit 1
    fi
    
    log_info "Cleaning up old images on Server $SERVER (keeping last $KEEP_COUNT)..."
    
    ssh -p${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SSH_HOST} << EOF
        # Remove old temp images
        sudo -u ${DEPLOY_USER} docker images | grep '${IMAGE_NAME}' | grep 'temp' | tail -n +\$((KEEP_COUNT + 1)) | awk '{print \$3}' | xargs -r sudo -u ${DEPLOY_USER} docker rmi -f
        
        # Remove dangling images
        sudo -u ${DEPLOY_USER} docker image prune -f
        
        echo "✅ Cleanup completed"
EOF
}

##############################################################################
# Main Script
##############################################################################
main() {
    local COMMAND=$1
    local SERVER=${2:-""}
    
    case $COMMAND in
        build)
            IMAGE_TAG=$(build_image)
            echo "IMAGE_TAG=$IMAGE_TAG"
            ;;
        
        deploy)
            if [ -z "$SERVER" ]; then
                log_error "Server parameter required (131, 130, or both)"
                exit 1
            fi
            
            IMAGE_TAG=${3:-"latest-temp"}
            
            if [ "$SERVER" = "both" ]; then
                deploy_server "131" "$IMAGE_TAG" && deploy_server "130" "$IMAGE_TAG"
            else
                deploy_server "$SERVER" "$IMAGE_TAG"
            fi
            ;;
        
        health-check)
            if [ -z "$SERVER" ]; then
                log_error "Server parameter required (131 or 130)"
                exit 1
            fi
            
            if [ "$SERVER" = "131" ]; then
                CONTAINERS="--filter 'name=airflow_2.11-mysql_8.0' --filter 'name=airflow_2.11-scheduler_2'"
            else
                CONTAINERS="--filter 'name=airflow_2.11-webserver' --filter 'name=airflow_2.11-scheduler_1'"
            fi
            
            health_check "$SERVER" "$CONTAINERS"
            ;;
        
        rollback)
            if [ -z "$SERVER" ]; then
                log_error "Server parameter required (131, 130, or both)"
                exit 1
            fi
            
            if [ "$SERVER" = "both" ]; then
                rollback_server "131" && rollback_server "130"
            else
                rollback_server "$SERVER"
            fi
            ;;
        
        status)
            if [ -z "$SERVER" ]; then
                log_error "Server parameter required (131, 130, or both)"
                exit 1
            fi
            
            if [ "$SERVER" = "both" ]; then
                show_status "131"
                echo ""
                show_status "130"
            else
                show_status "$SERVER"
            fi
            ;;
        
        cleanup)
            if [ -z "$SERVER" ]; then
                log_error "Server parameter required (131, 130, or both)"
                exit 1
            fi
            
            if [ "$SERVER" = "both" ]; then
                cleanup_images "131" && cleanup_images "130"
            else
                cleanup_images "$SERVER"
            fi
            ;;
        
        *)
            echo "Usage: $0 [command] [server] [options]"
            echo ""
            echo "Commands:"
            echo "  build                  - Build Docker image on Server 131"
            echo "  deploy [server] [tag]  - Deploy to specified server"
            echo "  health-check [server]  - Check container health"
            echo "  rollback [server]      - Rollback to stable image"
            echo "  status [server]        - Show deployment status"
            echo "  cleanup [server]       - Clean up old images"
            echo ""
            echo "Servers: 131, 130, both"
            echo ""
            echo "Examples:"
            echo "  $0 build"
            echo "  $0 deploy 131 20240112-temp"
            echo "  $0 health-check 130"
            echo "  $0 rollback both"
            echo "  $0 status both"
            exit 1
            ;;
    esac
}

# Run main function
if [ $# -lt 1 ]; then
    main "help"
else
    main "$@"
fi
