from typing import List, Optional

import os
import vertexai
from logging.config import dictConfig
from cloudevents.http import from_http
from vertexai.language_models import TextEmbeddingInput, TextEmbeddingModel
from vertexai.generative_models import GenerativeModel, Part, GenerationConfig
from langchain_community.document_loaders import PyPDFLoader
from langchain_google_community import GCSFileLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_core.prompts import PromptTemplate
from google.cloud import firestore, storage
from google.cloud.firestore_v1.vector import Vector
from google.cloud.firestore_v1.base_vector_query import DistanceMeasure
from flask import Flask, request, jsonify
from nanoid import generate

# Logging config
dictConfig({
    'version': 1,
    'formatters': {'default': {
        'format': '[%(asctime)s] %(levelname)s in %(module)s: %(message)s',
    }},
    'handlers': {'wsgi': {
        'class': 'logging.StreamHandler',
        'stream': 'ext://sys.stdout',
        'formatter': 'default'
    }},
    'root': {
        'level': 'INFO',
        'handlers': ['wsgi']
    }
})

# Global variables for Google Cloud SDK
PROJECT_ID = ""
VERTEX_AI_LOCATION = ""
EMBEDDING_MODEL = "text-multilingual-embedding-002"
EMBEDDING_DIMENSIONS = 768
EMBEDDING_PAGE_COUNT_AT_ONCE = 100
LLM_MODEL = "gemini-1.5-flash-001"
SPLITTER_CHUNK_SIZE = 500
SPLITTER_CHUNK_OVERLAP = 100
MAX_SUMMARIZATION_LENGTH = 2048
SUMMARIZATION_FAILED_MESSAGE = "申し訳ございません。要約の生成に失敗しました。"

app = Flask(__name__)
app.config.from_prefixed_env()

# Obtain project_id from environment variable and will raise exception if not set
try:
    PROJECT_ID = app.config["PROJECT_ID"]
except KeyError:
    raise Exception("Set FLASK_PROJECT_ID environment variable.")

# Obtain vertex_ai_location from environment variable or use the default value
try:
    VERTEX_AI_LOCATION = app.config["VERTEX_AI_LOCATION"]
except KeyError:
    VERTEX_AI_LOCATION = "us-central1"

vertexai.init(project=PROJECT_ID, location=VERTEX_AI_LOCATION)
db = firestore.Client()

bucket_name = f"{PROJECT_ID}-bucket"

def embed_texts(
    texts: list = None,
    task: str = "RETRIEVAL_DOCUMENT",
    dimensionality: Optional[int] = EMBEDDING_DIMENSIONS,
) -> List[List[float]]:
    model = TextEmbeddingModel.from_pretrained(EMBEDDING_MODEL)
    texts_list = [texts[i:i+EMBEDDING_PAGE_COUNT_AT_ONCE] for i in range(0, len(texts), EMBEDDING_PAGE_COUNT_AT_ONCE)]
    result = []
    for text_list in texts_list:
        inputs = [TextEmbeddingInput(text, task) for text in text_list]
        kwargs = dict(output_dimensionality=dimensionality) if dimensionality else {}
        embeddings = model.get_embeddings(inputs, **kwargs)
        result += [embedding.values for embedding in embeddings]
    return result

def load_pdf(file_path):
    return PyPDFLoader(file_path)

@app.route("/register_doc", methods=["POST"])
def register_doc():
    # Read metadata from Pub/Sub event
    event = from_http(request.headers, request.get_data())
    event_id = event.get("id")
    data = event.data
    content_type, bucket_name, name = data["contentType"], data["bucket"], data["name"]
    user_id, filename = data["name"].split("/")[0], data["name"].split("/")[1]
    file_id = filename[:21]
    _, ext = os.path.splitext(name)

    app.logger.info(f"{event_id}: start registring a doc: {file_id}")

    # Return when the file is not a PDF file
    if content_type != "application/pdf" or ext.lower() != ".pdf":
        app.logger.info(f"{event_id}: skipping registring a doc since the file is not PDF format: {file_id}")
        return ("The file is not a PDF file", 204)

    # Load PDF on Cloud Storage
    loader = GCSFileLoader(project_name=PROJECT_ID, bucket=bucket_name, blob=name, loader_func=load_pdf)
    documents = loader.load()

    # Split PDF
    text_splitter = RecursiveCharacterTextSplitter(
        separators=["\n", "。"],
        chunk_size=SPLITTER_CHUNK_SIZE,
        chunk_overlap=SPLITTER_CHUNK_OVERLAP,
        length_function=len,
    )
    pages = text_splitter.split_documents(documents)
    app.logger.info(f"{event_id}: identified {len(pages)} pages on {file_id}")

    # Generate embeddings using page content
    pages_content = [page.page_content for page in pages]

    app.logger.info(f"{event_id}: start embedding {len(pages_content)} texts")
    content_embeddings = embed_texts(pages_content)
    app.logger.info(f"{event_id}: finished embedding {len(pages_content)} texts")

    # Transform data to Firestore format
    docs = [{"text": page.page_content,
             "source": filename,
             "page": page.metadata['page'],
             "embedding": Vector(content_embedding)}
             for page, content_embedding in zip(pages, content_embeddings)]
    
    # Store result on Firestore 
    # Batch write 500 documents at once to make sure it won't exceed API limit size (10MB)
    app.logger.info(f"{event_id}: start storing embeddings into Firestore")
    docs_list = [docs[i:i+500] for i in range(0, len(docs), 500)]
    for doc_list in docs_list:
        batch = db.batch()
        for doc in doc_list:
            doc_ref = db.collection('users').document(user_id).collection("embeddings").document()
            batch.set(doc_ref, doc)
        batch.commit()
    app.logger.info(f"{event_id}: finished storing embeddings into Firestore")

    # Update the embedded flag to True
    app.logger.info(f"{event_id}: start updating embedding flag to True")
    doc_ref = db.collection("users").document(user_id).collection("items").document(file_id)
    doc_ref.update({"embedded": True})
    app.logger.info(f"{event_id}: finished updating embedding flag to True")

    app.logger.info(f"{event_id}: finished registring a doc: {file_id}")

    return ("Successfully registered", 204)


@app.route("/search", methods=["POST"])
def search():
    search_id = generate()

    # Validate POST data
    data = request.get_json()
    if data.get("question", None) is None or len(data["question"]) == 0:
        app.logger.info(f"{search_id}: failed to process search: invalid question")
        return ("A question is invalid (None or length = 0)", 400)
    
    if data.get("user_id", None) is None or len(data["user_id"]) == 0:
        app.logger.info(f"{search_id}: failed to process search: invalid user_id")
        return ("Please send a user_id", 400)
    
    user_id, question = data.get("user_id"),data.get("question")

    app.logger.info(f"{search_id}: start searching by {user_id}: {question}")
    
    # Generate embedding from question
    app.logger.info(f"{search_id}: start generating embedding from question")
    query_embedding = embed_texts(texts=[question], task = "RETRIEVAL_QUERY")[0]
    app.logger.info(f"{search_id}: finished generating embedding from question")

    # Search relevant documents with Vector Search
    app.logger.info(f"{search_id}: start vector search")
    vector_query = db.collection("users").document(user_id).collection("embeddings").find_nearest(
        vector_field="embedding",
        query_vector=Vector(query_embedding),
        distance_measure=DistanceMeasure.EUCLIDEAN,
        limit=3,
    )
    docs = [doc for doc in vector_query.stream()]
    if not docs:
        app.logger.info(f"{search_id}: no relevant documents found")
        return ("No relevant documents found", 400)
    app.logger.info(f"{search_id}: finished vector search and found {len(docs)} relevant documents")

    context, page, source = docs[0].get('text'), docs[0].get('page'), docs[0].get('source')
    
    # Create prompt using the context fetched above to ask Gemini
    template = """
    Answer to the question using the following context.
    If you couldn't find the answer, reply as "I couldn't find the answer."
    Generate the answer in Japanese.

    CONTEXT: {context}

    QUESTION: {question}
"""
    prompt = PromptTemplate(
        input_variables=["context", "question"],
        template=template,
    )
    final_prompt = prompt.format(context=context, question=question)

    # Ask Gemini
    app.logger.info(f"{search_id}: start generating answer by Gemini")
    model = GenerativeModel(model_name=LLM_MODEL)
    response = model.generate_content(final_prompt)
    app.logger.info(f"{search_id}: finished generating answer by Gemini")

    app.logger.info(f"{search_id}: finished searching by {user_id}: {question}")

    # Return the answer from Gemini in JSON format
    return jsonify({
        "answer": response.text,
        "metadata": {
            "page": page,
            "source": source 
        }
    })

@app.route("/summarize", methods=["POST"])
def summarize():
    event = from_http(request.headers, request.get_data())
    event_id = event.get("id")
    data = event.data
    content_type, bucket_name, name = data["contentType"], data["bucket"], data["name"]
    user_id, filename = data["name"].split("/")[0], data["name"].split("/")[1]
    file_id = filename[:21]
    _, ext = os.path.splitext(name)

    app.logger.info(f"{event_id}: start summarizing a file: {file_id}")

    # Validate uploaded_file and return the file is not a PDF or an image file
    if ext.lower() not in ['.pdf', '.jpg', '.jpeg', '.png'] or content_type not in ['application/pdf', 'image/jpeg', 'image/png']:
        app.logger.info(f"{event_id}: skipping summarizing a file since the file is not PDF or image format: {file_id}")
        return ("the file is not pdf or image", 204)

    model = GenerativeModel(model_name=LLM_MODEL)
    gcs_path = f"gs://{bucket_name}/{name}"
    doc_part = Part.from_uri(gcs_path, content_type)
    config = GenerationConfig(
        max_output_tokens=MAX_SUMMARIZATION_LENGTH + 1000, temperature=0, top_p=1, top_k=32,
    )

    prompt = f"""You are an AI assistant.
    
    Summarize the contents for readers who doesn't have enough domain knowledge.
    Output the result in Japanese and the result must be less than {MAX_SUMMARIZATION_LENGTH} characters.
    """

    try:
        doc_ref = db.collection("users").document(user_id).collection("items").document(file_id)
        app.logger.info(f"{event_id}: start generating a summary for a file: {file_id}")
        response = model.generate_content([doc_part, prompt], generation_config=config)
        app.logger.info(f"{event_id}: finished generating a summary for a file: {file_id}")
        doc_ref.update({"description": response.text})
        app.logger.info(f"{event_id}: finished summarizing a file: {file_id}")
    except Exception as err:
        app.logger.info(f"{event_id}: failed generating a summary for a file: {file_id}")
        doc_ref.update({"description": SUMMARIZATION_FAILED_MESSAGE})
        app.logger.info(f"{event_id}: failed summarizing a file: {err=}, {type(err)=}")

    return ("finished", 204)

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
