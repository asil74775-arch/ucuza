FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN useradd -m app && mkdir -p /data/media && chown -R app /data /app
USER app
EXPOSE 8000
CMD ["sh", "-c", "python -m scripts.seed --no-demo && uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --proxy-headers"]
