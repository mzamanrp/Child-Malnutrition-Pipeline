import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random
import os

# ==========================================
# 1. OUTPUT FOLDER CONFIGURATION
# ==========================================
# Set your custom folder path here. 
# The 'r' before the string handles Windows backslashes automatically.
OUTPUT_DIR = r"C:\SQL\child_nutrition"

# Safely create the directory if it does not exist yet
os.makedirs(OUTPUT_DIR, exist_ok=True)
print(f"Target directory ready: {OUTPUT_DIR}")

# ==========================================
# 2. DATA SIZE CONFIGURATION
# ==========================================
NUM_CLINICS = 15
NUM_CHILDREN = 25000
NUM_SCREENINGS = 100000

print("Generating Data...")

# 3. Generate Clinics
districts = ['Coxs Bazar', 'Sylhet', 'Kurigram', 'Satkhira', 'Bandarban']
clinics_data = {
    'ClinicID': range(1, NUM_CLINICS + 1),
    'ClinicName': [f"Field Clinic {i:02d}" for i in range(1, NUM_CLINICS + 1)],
    'District': [random.choice(districts) for _ in range(NUM_CLINICS)]
}
df_clinics = pd.DataFrame(clinics_data)

# 4. Generate Children
start_dob = datetime(2021, 1, 1)
children_data = {
    'ChildID': range(1, NUM_CHILDREN + 1),
    'Gender': [random.choice(['Male', 'Female']) for _ in range(NUM_CHILDREN)],
    'DateOfBirth': [start_dob + timedelta(days=random.randint(0, 1000)) for _ in range(NUM_CHILDREN)]
}
df_children = pd.DataFrame(children_data)

# 5. Generate Screenings
# Generate dates in standard YYYY-MM-DD format
screening_dates = [datetime(2025, 1, 1) + timedelta(days=random.randint(0, 365)) for _ in range(NUM_SCREENINGS)]
child_ids = [random.randint(1, NUM_CHILDREN) for _ in range(NUM_SCREENINGS)]
clinic_ids = [random.randint(1, NUM_CLINICS) for _ in range(NUM_SCREENINGS)]

# Generate realistic MUAC scores (Normal > 12.5, MAM 11.5-12.4, SAM < 11.5)
muac_scores = np.random.normal(loc=13.0, scale=1.5, size=NUM_SCREENINGS)
muac_scores = np.clip(muac_scores, 9.0, 16.0) 

status = []
for muac in muac_scores:
    if muac < 11.5:
        status.append('SAM')
    elif muac <= 12.4:
        status.append('MAM')
    else:
        status.append('Normal')

screenings_data = {
    'ScreeningID': range(1, NUM_SCREENINGS + 1),
    'ChildID': child_ids,
    'ClinicID': clinic_ids,
    'ScreeningDate': [d.strftime('%Y-%m-%d') for d in screening_dates],
    'AgeInMonths': [random.randint(6, 59) for _ in range(NUM_SCREENINGS)], 
    'Weight_kg': np.round(np.random.normal(12, 3, NUM_SCREENINGS), 1),
    'Height_cm': np.round(np.random.normal(85, 10, NUM_SCREENINGS), 1),
    'MUAC_cm': np.round(muac_scores, 1),
    'Malnutrition_Status': status
}
df_screenings = pd.DataFrame(screenings_data)

# ==========================================
# 6. EXPORT TO CUSTOM FOLDER
# ==========================================
# os.path.join securely combines your folder path with the file name
df_clinics.to_csv(os.path.join(OUTPUT_DIR, 'dim_clinics.csv'), index=False)
df_children.to_csv(os.path.join(OUTPUT_DIR, 'dim_children.csv'), index=False)
df_screenings.to_csv(os.path.join(OUTPUT_DIR, 'fact_screenings.csv'), index=False)

print(f"Success! Generated {NUM_SCREENINGS} screening records.")
print(f"You can find your files here: {OUTPUT_DIR}")