import os, time, json
import asyncio
import asyncpg
import numpy as np
import firebase_admin
from google.cloud import storage
from google.cloud.sql.connector import Connector
from firebase_admin import firestore
from cloudevents.http import from_http
from flask import Flask, request, jsonify
from langchain.document_loaders import PyPDFLoader
from langchain.embeddings import VertexAIEmbeddings
from langchain.llms import VertexAI
from langchain import PromptTemplate
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.chains import AnalyzeDocumentChain
from langchain.chains.question_answering import load_qa_chain
from pgvector.asyncpg import register_vector


# Parameters
project_id = os.environ.get("PJID", None)
region = "asia-northeast1"
instance_name = "pg15-pgvector-demo"
database_name = "docs"
database_user = "docs-admin"
database_password = "handson"


firebase_app = firebase_admin.initialize_app()
app = Flask(__name__)


async def insert_doc(file_id:int, text:str, metadata:str, user_id:str, embeddings_data:list):
    loop = asyncio.get_running_loop()
    async with Connector(loop=loop) as connector:
        conn: asyncpg.Connection = await connector.connect_async(
            f"{project_id}:{region}:{instance_name}",
            "asyncpg",
            user=f"{database_user}",
            password=f"{database_password}",
            db=f"{database_name}",
        )

        await register_vector(conn)
        
        await conn.execute(
            "INSERT INTO docs_embeddings (document_id, content, metadata, user_id, embedding) VALUES ($1, $2, $3, $4, $5)",
            file_id,
            text,
            json.dumps(metadata),
            user_id,
            np.array(embeddings_data),
        )
        await conn.close()


async def search_doc(embeddings_data:list, user_id:str):
    loop = asyncio.get_running_loop()
    async with Connector(loop=loop) as connector:
        conn: asyncpg.Connection = await connector.connect_async(
            f"{project_id}:{region}:{instance_name}",
            "asyncpg",
            user=f"{database_user}",
            password=f"{database_password}",
            db=f"{database_name}",
        )

        await register_vector(conn)
        similarity_threshold = 0.0 # Now, not set the threshold. You can change the threshold.
        num_matches = 50

        # Find similar products to the query using cosine similarity search
        # over all vector embeddings. This new feature is provided by `pgvector`.
        results = await conn.fetch(
            """SELECT document_id, content, metadata, user_id, 1 - (embedding <=> $1) AS similarity
            FROM docs_embeddings
            WHERE 1 - (embedding <=> $1) > $2 AND user_id = $4
            ORDER BY similarity DESC
            LIMIT $3
            """,
            embeddings_data,
            similarity_threshold,
            num_matches,
            user_id
        )

        await conn.close()
        
        return results

    
def call_Palm(context:str, question:str):
    llm = VertexAI(
        model_name="text-bison@001",
        max_output_tokens=256,
        temperature=0.1,
        top_p=0.8,
        top_k=40,
        verbose=True,
    )
    
    template = """
    ###{context}###
    ###で囲まれたテキストから、"質問：{question}" に関連する情報を抽出してください。
    """
    
    prompt = PromptTemplate(
        input_variables=["context", "question"],
        template=template,
    )

    final_prompt = prompt.format(context=context, question=question)
    result = llm(final_prompt)

    return result


def download_from_gcs(bucket_name:str, name:str):
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(name)
    name = name.split("/")[-1]
    blob.download_to_filename(name)


def store_description(user_id:str, file_id:str, description:str):
    db = firestore.client()
    collection = "users/{}/items".format(user_id)
    print("Adding description to {}/{}".format(collection, file_id))

    doc_ref = db.collection(collection).document(file_id)
    
    # Wait for the document to be created on firestore.
    for _ in range(10):
      doc = doc_ref.get()
      if doc.exists:
        doc_ref.update({"description": description})
        print("Description: {}".format(description))
        break
      time.sleep(3)
    

@app.route("/")
def index():
    return "<p>This is Gen AI API</p>"


@app.post('/register_doc')
async def register_doc():
    """
    This handler is trigered from pubsub.
    """
    event = from_http(request.headers, request.data)
    data = event.data
    bucket_name = data["bucket"]
    name = data["name"]
    _, ext = os.path.splitext(name)
    
    print("Uploaded file: {}".format(name))

    if not ext.lower() == ".pdf":
        return ("This is not pdf file", 200)

    # download pdf form gcs
    download_from_gcs(bucket_name, name)
    user_id, name = name.split("/")[-2:]
    file_id, _ = os.path.splitext(name)
    
    # Generate summary of the pdf
    loader = PyPDFLoader(name)
    document = loader.load()
    llm = VertexAI(
        model_name="text-bison@001",
        max_output_tokens=256,
        temperature=0.1,
        top_p=0.8,
        top_k=40,
        verbose=True,
    )

    qa_chain = load_qa_chain(llm, chain_type="map_reduce")
    qa_document_chain = AnalyzeDocumentChain(combine_docs_chain=qa_chain)
    description = qa_document_chain.run(
        input_document=document[0].page_content[:5000],
        question="何についての文書ですか？日本語で2文にまとめて答えてください。")

    store_description(user_id, file_id, description)


    # Load pdf for generate embeddings
    loader = PyPDFLoader(name)
    text_splitter = RecursiveCharacterTextSplitter(
        separators=["\n", "。"],
        chunk_size=500,
        chunk_overlap=0,
        length_function=len,
    )
    pages = loader.load_and_split(text_splitter=text_splitter)
    
    # Create embeddings and inser data to Cloud SQL
    embeddings = VertexAIEmbeddings(model_name="textembedding-gecko-multilingual@latest")
    for c, page in enumerate(pages[:100]): # Limit the nubmer of pages to avoid timeout.
        embeddings_data = embeddings.embed_query(page.page_content)
        # Filtering data
        filtered_data = page.page_content.encode("utf-8").replace(b'\x00', b'').decode("utf-8")
        await insert_doc(name, filtered_data, page.metadata, user_id, embeddings_data)
        print("{}: processed chunk {} of {}".format(name, c, min([len(pages)-1, 99])))
        time.sleep(0.5)
        
    print("Successfully registered: {}".format(name))
    return ("Registered a doc in Cloud SQL", 200)


@app.post("/search")
async def search():
    """
    Doc search and call LLM with a prompt.
    """
    data = request.get_json()
    
    if data.get("question", None) is None or len(data["question"]) == 0:
        return ("A question is bad (None or length = 0)", 400)
    
    if data.get("user_id", None) is None or len(data["user_id"]) == 0:
        return ("Please send a user_id", 400)
    
    # Crate embeddings
    embeddings = VertexAIEmbeddings(model_name="textembedding-gecko-multilingual@latest")
    embeddings_data = embeddings.embed_query(data["question"])
    
    # Serch docs
    results = await search_doc(embeddings_data, data["user_id"])
    
    if len(results) == 0:
        return ("Can not find docs in Cloud SQL", 204)
    
    # Call LLM using first result
    llm_result = call_Palm(results[0]["content"], data["question"])
    
    # Create a response
    response = {
        "answer": llm_result,
        "metadata": json.loads(results[0]["metadata"])
    }
    
    return jsonify(response)


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8081)))
