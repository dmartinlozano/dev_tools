FROM python:3.13.3-slim
WORKDIR /app
RUN pip install pipenv
COPY Pipfile* ./
RUN pipenv install --deploy --system
COPY src/ ./src/
EXPOSE 8000
EXPOSE 443
ENV PORT=8000
CMD ["sh", "-c", "uvicorn src.api:app --host 0.0.0.0 --port $PORT"]
