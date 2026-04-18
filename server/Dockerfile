FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY observability/ .

EXPOSE 8000 8001

CMD ["gunicorn", "main.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "1"]
