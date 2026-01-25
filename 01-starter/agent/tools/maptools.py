"""
Google Maps tools for finding restaurants.

This tool is complete and ready to use - no modifications needed!
It uses the Google Maps API to search for restaurants near a location.
"""
import googlemaps
import os
import json
from dotenv import load_dotenv
import logging

load_dotenv()

logger = logging.getLogger(__name__)


def find_restaurants(location: str, radius_km: int = 5, keyword: str = None):
    """
    Finds restaurants near a given location within a specified radius.

    Args:
        location (str): The address or landmark to search near (e.g., "San Francisco", "Tokyo").
        radius_km (int): The search radius in kilometers. Default is 5km.
        keyword (str): Optional keyword to filter results (e.g., "Italian", "rooftop", "vegetarian", "halal").

    Returns:
        str: A JSON string representing a list of restaurants with detailed information.
    """
    search_desc = f"Finding restaurants near '{location}' with radius {radius_km}km"
    if keyword:
        search_desc += f" matching '{keyword}'"
    logger.info(search_desc)
    api_key = os.getenv("GOOGLE_MAPS_API_KEY")

    if not api_key:
        raise ValueError("Google Maps API key not found. Make sure to create a .env file with GOOGLE_MAPS_API_KEY=<YOUR_API_KEY>.")

    gmaps = googlemaps.Client(key=api_key)

    # Geocode the location to get latitude and longitude
    try:
        geocode_result = gmaps.geocode(location)
        if not geocode_result:
            return json.dumps({"error": "Could not geocode the provided location. Please provide a more specific address or landmark."})
        lat = geocode_result[0]['geometry']['location']['lat']
        lng = geocode_result[0]['geometry']['location']['lng']
    except Exception as e:
        return json.dumps({"error": f"An error occurred during geocoding: {e}"})

    # Search for nearby restaurants
    try:
        search_params = {
            "location": (lat, lng),
            "radius": radius_km * 1000,
            "type": "restaurant"
        }
        if keyword:
            search_params["keyword"] = keyword
        places_result = gmaps.places_nearby(**search_params)
    except Exception as e:
        return json.dumps({"error": f"An error occurred while searching for restaurants: {e}"})

    restaurants = []
    for place in places_result.get('results', []):
        place_id = place.get('place_id')
        if not place_id:
            continue

        try:
            place_details = gmaps.place(
                place_id=place_id,
                fields=['name', 'vicinity', 'rating', 'website', 'reviews', 'user_ratings_total']
            )['result']

            restaurant_info = {
                'name': place_details.get('name'),
                'address': place_details.get('vicinity'),
                'rating': place_details.get('rating'),
                'total_reviews': place_details.get('user_ratings_total'),
                'website': place_details.get('website'),
                'reviews': place_details.get('reviews')
            }
            restaurants.append(restaurant_info)

        except Exception as e:
            logger.warning(f"Could not fetch details for place_id {place_id}: {e}")

    logger.info(f"Found {len(restaurants)} restaurants. Returning JSON output.")
    return json.dumps(restaurants, indent=4)
