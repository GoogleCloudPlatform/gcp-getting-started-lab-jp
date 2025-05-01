# Movie search demo app

[GIF Video](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/movie_search_metadata/demo_app/docs/images/movie_search_demo.gif)

![](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/movie_search_metadata/demo_app/docs/images/movie_search_demo.gif)

## Instructions

After creating a new project, open Cloud Shell with a user with owner privileges and run the following commands:

### Get the code

```
git clone https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp.git
cd gcp-getting-started-lab-jp/movie_search_metadata/demo_app
```

The default output language is Japanese. To change it, modify the following part of `backend/prompt_content_search.py`:

```
[format instruction]
Output in Japanese. Output is a JSON list with "scene dict".
```

Change `Japanese` to your favorite language.

### Configure the Vertex AI Search search engine

```
./vais_setup.sh
```

The document import process takes about 20 to 30 minutes, so please be patient.

### Deploy the search app

```
./deploy.sh
```

When the deployment is complete, the app URL will be displayed as follows:

Application URL: `https://movie-search-app-xxxxxxxxxx-an.a.run.app`

You can use the following two functions by opening this URL in a browser:

  - File search: Searches for video files related to the query.
  - Scene search: Searches for scenes (video file + time stamp) related to the query.

The videos to be searched are limited to the three types of videos prepared in advance. Also, immediately after configuring Vertex AI Search, correct search results may not be obtained because index creation is incomplete. In that case, please try again after a few hours.

**Caution**

Anyone who knows the URL of the app can access it. It is recommended to shut down the project when the demo is finished to prevent unnecessary charges.
