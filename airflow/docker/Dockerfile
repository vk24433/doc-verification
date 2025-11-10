# Example Dockerfile for custom Airflow image
# Adjust this according to your needs

FROM apache/airflow:2.7.3-python3.10

# Build arguments for metadata
ARG BUILD_DATE
ARG VCS_REF
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.schema-version="1.0"

USER root

# Install any system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    vim \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Copy and install Python requirements
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Copy custom plugins, dags, or config files if needed
# COPY --chown=airflow:airflow plugins/ ${AIRFLOW_HOME}/plugins/
# COPY --chown=airflow:airflow dags/ ${AIRFLOW_HOME}/dags/

# Set any custom environment variables
ENV AIRFLOW__CORE__LOAD_EXAMPLES=False

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD airflow jobs check --job-type SchedulerJob --hostname $(hostname) || exit 1

USER airflow
WORKDIR ${AIRFLOW_HOME}
