# Use the official MySQL 8 image as a base
FROM mysql:8

# Copy the data dump into the container
COPY data/dump.sql /docker-entrypoint-initdb.d/
