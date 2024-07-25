#!/bin/bash
set -e

# Define variables
IMAGE_NAME="mysql8-preloaded"
CONTAINER_NAME="temp-mysql"
MYSQL_ROOT_PASSWORD="root"
DUMP_DIR="data"  # Directory where dump files are located
DOCKER_REGISTRY="nozus"  # Replace with your Docker registry username or address

# Prompt user for port mapping
read -p "Enter the port on your host to map to MySQL port 3306 (e.g., 3307): " HOST_PORT

# Build the Docker image
echo "Building Docker image..."
docker build -t $IMAGE_NAME .

# Create and start a container to run the database
echo "Creating and starting container..."
docker run --name $CONTAINER_NAME -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD -d -p $HOST_PORT:3306 $IMAGE_NAME

# Wait for MySQL to initialize
echo "Waiting for MySQL to initialize..."
for i in {1..30}; do
  if docker exec $CONTAINER_NAME mysqladmin --user=root --password=$MYSQL_ROOT_PASSWORD ping --silent; then
    echo "MySQL is ready."
    break
  fi
  sleep 5
done

# Copy and import all dump files
for DUMP_FILE in $DUMP_DIR/*.sql; do
  echo "Processing dump file: $DUMP_FILE"

  # Copy the dump file into the container
  echo "Copying dump file into container..."
  docker cp $DUMP_FILE $CONTAINER_NAME:/tmp/$(basename $DUMP_FILE)

  # Verify the file exists in the container
  echo "Verifying dump file in container..."
  docker exec $CONTAINER_NAME sh -c "ls -l /tmp/$(basename $DUMP_FILE)"

  # Import the data
  echo "Importing data from dump file..."
  docker exec -i $CONTAINER_NAME sh -c "mysql -uroot -p$MYSQL_ROOT_PASSWORD < /tmp/$(basename $DUMP_FILE)" || { echo "Import failed"; exit 1; }
done

# Commit the container to a new image with the data loaded
echo "Committing container to new image..."
NEW_TAG=$(date +%Y%m%d_%H%M%S)  # Use a more readable timestamp
docker commit $CONTAINER_NAME $IMAGE_NAME:$NEW_TAG

# Ask user if they want to publish the image
read -p "Do you want to publish the image? (y/n): " PUBLISH

if [[ "$PUBLISH" == "y" ]]; then
  # Ask where to publish
  read -p "Where do you want to publish the image? (dockerhub/local): " PUBLISH_LOCATION

  if [[ "$PUBLISH_LOCATION" == "dockerhub" ]]; then
    # Tag and push the image to Docker Hub
    echo "Tagging and pushing the image to Docker Hub..."
    docker tag $IMAGE_NAME:$NEW_TAG $DOCKER_REGISTRY/$IMAGE_NAME:$NEW_TAG
    docker push $DOCKER_REGISTRY/$IMAGE_NAME:$NEW_TAG

  elif [[ "$PUBLISH_LOCATION" == "local" ]]; then
    # Tag and push the image to local registry (if applicable)
    echo "Tagging and pushing the image to local registry..."
    docker tag $IMAGE_NAME:$NEW_TAG localhost:5000/$IMAGE_NAME:$NEW_TAG
    docker push localhost:5000/$IMAGE_NAME:$NEW_TAG

  else
    echo "Invalid option. Exiting without publishing."
  fi

  # Provide pull command
  echo "To pull the image, use the following command:"
  echo "docker pull $DOCKER_REGISTRY/$IMAGE_NAME:$NEW_TAG"
else
  echo "Skipping image publishing."
fi

# Clean up
echo "Cleaning up..."
docker rm -f $CONTAINER_NAME
docker rmi $IMAGE_NAME:$NEW_TAG

echo "Done!"

# Provide container run command
echo "To run the container with the new image in informational mode, use the following command:"
echo "docker run --name ${IMAGE_NAME}_info -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD -d -p $HOST_PORT:3306 $DOCKER_REGISTRY/$IMAGE_NAME:$NEW_TAG"
