FROM apache/airflow:2.11.0-python3.9

# Switch to root to install system packages
USER root

# Set timezone to Asia/Calcutta
RUN rm -rf /etc/localtime && \
    ln -s /usr/share/zoneinfo/Asia/Calcutta /etc/localtime

# Install system dependencies in a single layer to reduce image size
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        jq \
        nano \
        clickhouse-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch back to airflow user
USER airflow

# Install Python packages
# Using a single RUN command with --no-cache-dir to reduce image size
RUN pip install --no-cache-dir \
    PyMySQL \
    awscli \
    pymsteams==0.1.13 \
    kafka-python==2.0.2 \
    pika \
    pyathena \
    pyspark==3.3.0 \
    acryl-datahub==0.8.5.0

# Create AWS directory
RUN mkdir -p /home/airflow/.aws

# Add build metadata
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.version=$VERSION \
      org.label-schema.name="Airflow Custom" \
      org.label-schema.description="Custom Airflow image with additional dependencies" \
      org.label-schema.vendor="99acres"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
  CMD airflow jobs check --job-type SchedulerJob --hostname $(hostname) || exit 1

# Default command (can be overridden in docker-compose)
CMD ["scheduler"]
