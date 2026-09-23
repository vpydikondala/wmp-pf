# Processor service

Long-running SQS consumer. It reads the durable S3 raw object referenced by each processing message, normalises common occupancy fields, upserts the event into PostgreSQL, then publishes a compact analytical record to the data-lake delivery queue.

The processing SQS message is deleted only after S3 read, database commit and data-lake queue publish all succeed; otherwise it remains for retry and eventual DLQ redrive.
