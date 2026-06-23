import csv
import json
import os

def convert_csv_to_json(csv_path, json_path):
    print(f"Converting CSV: {csv_path} -> {json_path}")
    if not os.path.exists(csv_path):
        print(f"Error: File not found: {csv_path}")
        return

    records = []
    # 수도권 바운딩 박스 정의 (서울, 경기, 인천)
    min_lat, max_lat = 36.9, 38.3
    min_lng, max_lng = 126.2, 127.8

    with open(csv_path, 'r', encoding='cp949', errors='ignore') as f:
        reader = csv.DictReader(f)
        for row in reader:
            name = (row.get('화장실명') or '').strip()
            lat_str = row.get('WGS84위도') or row.get('위도') or ''
            lng_str = row.get('WGS84경도') or row.get('경도') or ''
            address = (row.get('소재지도로명주소') or row.get('소재지지번주소') or '').strip()

            if not name or not lat_str or not lng_str:
                continue

            try:
                lat = float(lat_str)
                lng = float(lng_str)
            except ValueError:
                continue

            # 수도권 영역 필터링으로 속도/용량 대폭 최적화
            if lat < min_lat or lat > max_lat or lng < min_lng or lng > max_lng:
                continue

            records.append({
                "name": name,
                "lat": lat,
                "lng": lng,
                "address": address
            })

    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(records, f, ensure_ascii=False, indent=2)

    print(f"Successfully processed {len(records)} Metropolitian toilets.")

if __name__ == "__main__":
    base_dir = r"c:\Users\User\Desktop\Project Achasan\assets\data"
    
    toilet_csv = os.path.join(base_dir, "공중화장실정보.csv")
    toilet_json = os.path.join(base_dir, "gis_toilets.json")
    convert_csv_to_json(toilet_csv, toilet_json)
