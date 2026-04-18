import logging
import os

import pyroscope
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.prometheus import PrometheusMetricReader
from opentelemetry.instrumentation.django import DjangoInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from pythonjsonlogger.json import JsonFormatter


def setup():
    service_name = os.getenv("OTEL_SERVICE_NAME", "django-observability")
    resource = Resource({"service.name": service_name})

    # Traces → OTLP gRPC → otel-collector → Jaeger
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(
        BatchSpanProcessor(
            OTLPSpanExporter(
                endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
            )
        )
    )
    trace.set_tracer_provider(tracer_provider)

    # Metrics → served via Django /metrics view
    meter_provider = MeterProvider(resource=resource, metric_readers=[PrometheusMetricReader()])
    metrics.set_meter_provider(meter_provider)

    # Auto-instrument Django requests and inject trace IDs into log records
    DjangoInstrumentor().instrument()
    LoggingInstrumentor().instrument(set_logging_format=False)

    # JSON structured logs → stdout → Alloy → Loki
    handler = logging.StreamHandler()
    handler.setFormatter(
        JsonFormatter("%(asctime)s %(levelname)s %(name)s %(message)s %(otelTraceID)s %(otelSpanID)s")
    )
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)

    # Flame graphs → Pyroscope distributor
    pyroscope.configure(
        application_name=service_name,
        server_address=os.getenv("PYROSCOPE_SERVER_ADDRESS", "http://localhost:4040"),
    )
