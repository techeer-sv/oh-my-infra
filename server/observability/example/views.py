import logging
import math

from drf_spectacular.utils import OpenApiParameter, extend_schema
from opentelemetry import metrics, trace
from rest_framework.decorators import api_view
from rest_framework.response import Response

logger = logging.getLogger(__name__)

tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

request_counter = meter.create_counter(
    "example_requests_total",
    description="Total requests per endpoint",
)
compute_histogram = meter.create_histogram(
    "example_compute_duration_ms",
    description="Time spent in compute endpoint",
    unit="ms",
)


@extend_schema(responses={200: {"type": "object", "properties": {"status": {"type": "string"}}}})
@api_view(["GET"])
def health(request):
    logger.info("health check")
    return Response({"status": "ok"})


@extend_schema(
    parameters=[OpenApiParameter("n", int, description="Range size for sqrt sum", default=1000)],
    responses={200: {"type": "object", "properties": {"n": {"type": "integer"}, "result": {"type": "number"}}}},
)
@api_view(["GET"])
def compute(request):
    n = int(request.GET.get("n", 1000))

    with tracer.start_as_current_span("compute") as span:
        span.set_attribute("compute.n", n)
        request_counter.add(1, {"endpoint": "compute"})

        result = sum(math.sqrt(i) for i in range(n))
        compute_histogram.record(n / 10, {"endpoint": "compute"})

        logger.info("compute finished", extra={"n": n, "result": result})
        return Response({"n": n, "result": result})


@extend_schema(responses={500: {"type": "object", "properties": {"error": {"type": "string"}}}})
@api_view(["GET"])
def fail(request):
    with tracer.start_as_current_span("fail") as span:
        request_counter.add(1, {"endpoint": "fail"})
        try:
            raise ValueError("intentional error for tracing demo")
        except ValueError as exc:
            span.record_exception(exc)
            logger.error("handled error", extra={"error": str(exc)})
            return Response({"error": str(exc)}, status=500)
