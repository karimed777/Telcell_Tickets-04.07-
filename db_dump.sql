--
-- PostgreSQL database dump
--

\restrict PzWoxAIzodGPCAkl3nzF9XrNgaue66xCa85QK57uEAzer26pwXVbkBitwxuMDvL

-- Dumped from database version 16.14
-- Dumped by pg_dump version 16.14

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: EventFloors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."EventFloors" (
    "Id" uuid NOT NULL,
    "EventLayoutId" uuid NOT NULL,
    "Name" text NOT NULL,
    "Order" integer NOT NULL
);


ALTER TABLE public."EventFloors" OWNER TO postgres;

--
-- Name: EventLayouts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."EventLayouts" (
    "Id" uuid NOT NULL,
    "EventId" uuid NOT NULL,
    "VenueLayoutId" uuid,
    "HasSeatingPlan" boolean NOT NULL
);


ALTER TABLE public."EventLayouts" OWNER TO postgres;

--
-- Name: EventSeatBlocks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."EventSeatBlocks" (
    "Id" uuid NOT NULL,
    "EventFloorId" uuid NOT NULL,
    "SeatType" text NOT NULL,
    "DefaultPrice" numeric(12,2) NOT NULL,
    "DefaultDescription" text,
    "DefaultColor" text NOT NULL,
    "CanvasX" double precision NOT NULL,
    "CanvasY" double precision NOT NULL,
    "RotationDeg" double precision NOT NULL,
    "Rows" integer NOT NULL,
    "SeatsPerRow" integer NOT NULL
);


ALTER TABLE public."EventSeatBlocks" OWNER TO postgres;

--
-- Name: EventSeats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."EventSeats" (
    "Id" uuid NOT NULL,
    "EventSeatBlockId" uuid NOT NULL,
    "Row" integer NOT NULL,
    "Number" integer NOT NULL,
    "SeatType" text NOT NULL,
    "Price" numeric(12,2) NOT NULL,
    "Description" text,
    "Color" text NOT NULL,
    "CanvasX" double precision NOT NULL,
    "CanvasY" double precision NOT NULL,
    "IsActive" boolean NOT NULL,
    "Status" text NOT NULL,
    "ReservedByUserId" uuid,
    "ReservedAt" timestamp with time zone,
    "OrderId" uuid
);


ALTER TABLE public."EventSeats" OWNER TO postgres;

--
-- Name: EventStages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."EventStages" (
    "Id" uuid NOT NULL,
    "EventFloorId" uuid NOT NULL,
    "CanvasX" double precision NOT NULL,
    "CanvasY" double precision NOT NULL,
    "Width" double precision NOT NULL,
    "Height" double precision NOT NULL,
    "Label" text NOT NULL
);


ALTER TABLE public."EventStages" OWNER TO postgres;

--
-- Name: Events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Events" (
    "Id" uuid NOT NULL,
    "Title" text NOT NULL,
    "Description" text NOT NULL,
    "Category" text NOT NULL,
    "StartsAt" timestamp with time zone NOT NULL,
    "CoverColorHex" text NOT NULL,
    "CoverImageUrl" text,
    "VenueId" uuid NOT NULL,
    "IsFeatured" boolean NOT NULL,
    "CreatedAt" timestamp with time zone NOT NULL,
    "DescriptionAm" text DEFAULT ''::text NOT NULL,
    "TitleAm" text DEFAULT ''::text NOT NULL
);


ALTER TABLE public."Events" OWNER TO postgres;

--
-- Name: Orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Orders" (
    "Id" uuid NOT NULL,
    "UserId" uuid NOT NULL,
    "Total" numeric(12,2) NOT NULL,
    "Currency" text NOT NULL,
    "Status" text NOT NULL,
    "CreatedAt" timestamp with time zone NOT NULL,
    "PaidAt" timestamp with time zone
);


ALTER TABLE public."Orders" OWNER TO postgres;

--
-- Name: SeatBlocks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."SeatBlocks" (
    "Id" uuid NOT NULL,
    "VenueFloorId" uuid NOT NULL,
    "SeatType" text NOT NULL,
    "DefaultPrice" numeric(12,2) NOT NULL,
    "DefaultDescription" text,
    "DefaultColor" text NOT NULL,
    "CanvasX" double precision NOT NULL,
    "CanvasY" double precision NOT NULL,
    "RotationDeg" double precision NOT NULL,
    "Rows" integer NOT NULL,
    "SeatsPerRow" integer NOT NULL
);


ALTER TABLE public."SeatBlocks" OWNER TO postgres;

--
-- Name: SeatReservations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."SeatReservations" (
    "Id" uuid NOT NULL,
    "EventId" uuid NOT NULL,
    "SessionId" text NOT NULL,
    "EventSeatId" uuid NOT NULL,
    "ReservedAt" timestamp with time zone NOT NULL,
    "ExpiresAt" timestamp with time zone NOT NULL
);


ALTER TABLE public."SeatReservations" OWNER TO postgres;

--
-- Name: Seats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Seats" (
    "Id" uuid NOT NULL,
    "SeatBlockId" uuid NOT NULL,
    "Row" integer NOT NULL,
    "Number" integer NOT NULL,
    "SeatType" text NOT NULL,
    "Price" numeric(12,2) NOT NULL,
    "Description" text,
    "Color" text NOT NULL,
    "CanvasX" double precision NOT NULL,
    "CanvasY" double precision NOT NULL,
    "IsActive" boolean NOT NULL
);


ALTER TABLE public."Seats" OWNER TO postgres;

--
-- Name: Stages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Stages" (
    "Id" uuid NOT NULL,
    "VenueFloorId" uuid NOT NULL,
    "CanvasX" double precision NOT NULL,
    "CanvasY" double precision NOT NULL,
    "Width" double precision NOT NULL,
    "Height" double precision NOT NULL,
    "Label" text NOT NULL
);


ALTER TABLE public."Stages" OWNER TO postgres;

--
-- Name: TicketTypes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."TicketTypes" (
    "Id" uuid NOT NULL,
    "Name" text NOT NULL,
    "Price" numeric(12,2) NOT NULL,
    "Currency" text NOT NULL,
    "Quantity" integer NOT NULL,
    "Sold" integer NOT NULL,
    "EventId" uuid NOT NULL,
    "NameAm" text DEFAULT ''::text NOT NULL
);


ALTER TABLE public."TicketTypes" OWNER TO postgres;

--
-- Name: Tickets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Tickets" (
    "Id" uuid NOT NULL,
    "OrderId" uuid NOT NULL,
    "TicketTypeId" uuid,
    "EventId" uuid NOT NULL,
    "QrToken" text NOT NULL,
    "Status" text NOT NULL,
    "IssuedAt" timestamp with time zone NOT NULL,
    "CheckedInAt" timestamp with time zone,
    "TransferredTo" text,
    "TransferredAt" timestamp with time zone,
    "AppUserId" uuid,
    "EventSeatId" uuid,
    "Price" numeric(12,2) DEFAULT 0.0 NOT NULL,
    "TypeName" text DEFAULT ''::text NOT NULL
);


ALTER TABLE public."Tickets" OWNER TO postgres;

--
-- Name: Users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Users" (
    "Id" uuid NOT NULL,
    "DisplayName" text NOT NULL,
    "Phone" text NOT NULL,
    "City" text NOT NULL,
    "CreatedAt" timestamp with time zone NOT NULL,
    "OtpCode" text,
    "OtpExpiresAt" timestamp with time zone,
    "SessionToken" text,
    "Email" text,
    "IsAdmin" boolean DEFAULT false NOT NULL
);


ALTER TABLE public."Users" OWNER TO postgres;

--
-- Name: VenueFloors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."VenueFloors" (
    "Id" uuid NOT NULL,
    "VenueLayoutId" uuid NOT NULL,
    "Name" text NOT NULL,
    "Order" integer NOT NULL
);


ALTER TABLE public."VenueFloors" OWNER TO postgres;

--
-- Name: VenueLayouts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."VenueLayouts" (
    "Id" uuid NOT NULL,
    "VenueId" uuid NOT NULL,
    "Name" text NOT NULL,
    "CreatedAt" timestamp with time zone NOT NULL
);


ALTER TABLE public."VenueLayouts" OWNER TO postgres;

--
-- Name: Venues; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Venues" (
    "Id" uuid NOT NULL,
    "Name" text NOT NULL,
    "City" text NOT NULL,
    "Address" text NOT NULL,
    "Latitude" double precision NOT NULL,
    "Longitude" double precision NOT NULL,
    "AddressAm" text DEFAULT ''::text NOT NULL,
    "NameAm" text DEFAULT ''::text NOT NULL
);


ALTER TABLE public."Venues" OWNER TO postgres;

--
-- Name: __EFMigrationsHistory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."__EFMigrationsHistory" (
    "MigrationId" character varying(150) NOT NULL,
    "ProductVersion" character varying(32) NOT NULL
);


ALTER TABLE public."__EFMigrationsHistory" OWNER TO postgres;

--
-- Data for Name: EventFloors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."EventFloors" ("Id", "EventLayoutId", "Name", "Order") FROM stdin;
91cf5ecb-c176-4f65-8a81-2bfc45f4a618	55b7c7c5-e783-44c2-8b67-f0830d5da2ff	Партер	0
\.


--
-- Data for Name: EventLayouts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."EventLayouts" ("Id", "EventId", "VenueLayoutId", "HasSeatingPlan") FROM stdin;
55b7c7c5-e783-44c2-8b67-f0830d5da2ff	2b570bea-d33c-44d7-967a-85a75bfe5802	5cace409-e210-4ba8-9cc1-f0e35140aaf4	t
\.


--
-- Data for Name: EventSeatBlocks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."EventSeatBlocks" ("Id", "EventFloorId", "SeatType", "DefaultPrice", "DefaultDescription", "DefaultColor", "CanvasX", "CanvasY", "RotationDeg", "Rows", "SeatsPerRow") FROM stdin;
0feea61c-b43b-4feb-b64f-bdd3f0fdcdb4	91cf5ecb-c176-4f65-8a81-2bfc45f4a618	VIP	15000.00	VIP с обслуживанием	#FFD700	0	0	0	2	3
\.


--
-- Data for Name: EventSeats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."EventSeats" ("Id", "EventSeatBlockId", "Row", "Number", "SeatType", "Price", "Description", "Color", "CanvasX", "CanvasY", "IsActive", "Status", "ReservedByUserId", "ReservedAt", "OrderId") FROM stdin;
3149d7a4-d8e3-4edd-95e1-48fae9484062	0feea61c-b43b-4feb-b64f-bdd3f0fdcdb4	2	6	VIP	15000.00	\N	#FFD700	46	23	t	Available	\N	\N	\N
466d0b48-a641-4b5e-af8a-3a272a990d07	0feea61c-b43b-4feb-b64f-bdd3f0fdcdb4	1	1	VIP	15000.00	\N	#FFD700	-46	-23	t	Available	\N	\N	\N
7d23f82b-7195-4be8-8e8e-dce23906e2a1	0feea61c-b43b-4feb-b64f-bdd3f0fdcdb4	1	3	VIP	15000.00	\N	#FFD700	46	-23	t	Available	\N	\N	\N
98cbe0b6-7eee-42f6-a154-9b90b4515d0b	0feea61c-b43b-4feb-b64f-bdd3f0fdcdb4	2	5	VIP	15000.00	\N	#FFD700	0	23	t	Available	\N	\N	\N
b10658d0-6d7f-44a2-8501-7e32b36d478a	0feea61c-b43b-4feb-b64f-bdd3f0fdcdb4	2	4	VIP	15000.00	\N	#FFD700	-46	23	t	Available	\N	\N	\N
bdf0184a-6957-47b0-883a-adced91d6e29	0feea61c-b43b-4feb-b64f-bdd3f0fdcdb4	1	2	VIP	15000.00	\N	#FFD700	0	-23	t	Available	\N	\N	\N
\.


--
-- Data for Name: EventStages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."EventStages" ("Id", "EventFloorId", "CanvasX", "CanvasY", "Width", "Height", "Label") FROM stdin;
0c8304d0-206e-450d-9852-9dfc7ac90ecb	91cf5ecb-c176-4f65-8a81-2bfc45f4a618	0	-200	240	64	СЦЕНА
\.


--
-- Data for Name: Events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Events" ("Id", "Title", "Description", "Category", "StartsAt", "CoverColorHex", "CoverImageUrl", "VenueId", "IsFeatured", "CreatedAt", "DescriptionAm", "TitleAm") FROM stdin;
a0b6368e-822d-4fd5-bea5-becff7ae080b	System of a Down · Yerevan	Легендарная группа возвращается в Ереван с большим стадионным шоу.	Concert	2026-07-22 03:00:00+07	#7B2FF7	https://upload.wikimedia.org/wikipedia/commons/thumb/7/7f/System_of_a_Down_live_in_Astana.jpg/1280px-System_of_a_Down_live_in_Astana.jpg	4a6a2585-77a7-452b-9176-6dcd00a120ec	t	2026-07-02 22:06:01.303157+07	Լեգենդար խումբը վերադառնում է Երևան մեծ ստադիոնային շոուով։	System of a Down · Երևան
009b0bb3-7b2e-44f9-a708-aebbc32c734f	Лебединое озеро	Классический балет Чайковского в постановке Национального театра.	Theatre	2026-07-09 02:00:00+07	#1F6FB2	https://upload.wikimedia.org/wikipedia/commons/thumb/1/19/%C3%93pera%2C_Erev%C3%A1n%2C_Armenia%2C_2016-10-03%2C_DD_12.jpg/1280px-%C3%93pera%2C_Erev%C3%A1n%2C_Armenia%2C_2016-10-03%2C_DD_12.jpg	4ce0f111-56ba-4de5-ac4b-563c9ba48dd6	f	2026-07-02 22:06:01.375828+07	Չայկովսկու դասական բալետը Ազգային թատրոնի բեմադրությամբ։	Կարապի լիճը
8e37eff8-3f80-4182-bd73-586b861e3919	Yerevan Wine Days	Главный винный фестиваль года: дегустации, музыка, гастрономия.	Festival	2026-07-15 23:00:00+07	#B0203C	https://upload.wikimedia.org/wikipedia/commons/thumb/0/0e/Wine_Bottles.jpg/1280px-Wine_Bottles.jpg	1e99bfde-3c55-4072-9068-9cd741d94168	t	2026-07-02 22:06:01.378698+07	Տարվա գլխավոր գինու փառատոն՝ համտեսում, երաժշտություն, գաստրոնոմիա։	Yerevan Wine Days
b2a87ebc-b5d9-4938-86bf-cfc1ddd7bfae	Tech Summit Armenia 2026	Крупнейшая IT-конференция региона: спикеры, нетворкинг, стартапы.	Conference	2026-08-01 17:00:00+07	#0E7C7B	https://upload.wikimedia.org/wikipedia/commons/thumb/e/e4/Conference_audience.jpg/1280px-Conference_audience.jpg	f363fa2a-71d6-444a-a7e5-d28a33cc50ff	f	2026-07-02 22:06:01.380405+07	Տարածաշրջանի խոշորագույն IT-կոնֆերանսը՝ բանախոսներ, ցանցավորում, ստարտափներ։	Tech Summit Armenia 2026
563e8692-6b49-4c03-b47b-4d038280f165	Армянский симфонический оркестр	Вечер классической музыки в зале Демирчяна.	Concert	2026-07-12 02:00:00+07	#2E2A6B	https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Karen_Demirchyan_Sports_and_Concerts_Complex_shot_from_air%2C_May_2019.jpg/1280px-Karen_Demirchyan_Sports_and_Concerts_Complex_shot_from_air%2C_May_2019.jpg	3516ca9a-6893-4f9b-9d11-d2f8192770e7	f	2026-07-02 22:06:01.382666+07	Դասական երաժշտության երեկո Դեմիրճյանի սրահում։	Հայկական սիմֆոնիկ նվագախումբ
2b570bea-d33c-44d7-967a-85a75bfe5802	Modern Art Expo	Выставка современного искусства армянских и зарубежных авторов.	Exhibition	2026-07-05 18:00:00+07	#5A4A8A	https://upload.wikimedia.org/wikipedia/commons/thumb/3/32/Art_exhibition.jpg/1280px-Art_exhibition.jpg	f363fa2a-71d6-444a-a7e5-d28a33cc50ff	f	2026-07-02 22:06:01.38449+07	Հայ և օտարերկրյա հեղինակների ժամանակակից արվեստի ցուցահանդես։	Modern Art Expo
7a137412-0e28-4678-8e9e-62d7c82ad3f1	KALEO в Ереване	Исландская рок-группа KALEO впервые в Ереване с хитами Way Down We Go и No Good.	Concert	2026-07-28 03:00:00+07	#1C1C24	https://upload.wikimedia.org/wikipedia/commons/f/f5/20180603_N%C3%BCrnberg_Rock_im_Park_Kaleo_0212.jpg	3516ca9a-6893-4f9b-9d11-d2f8192770e7	t	2026-07-02 22:06:01.385792+07	Իսլանդական KALEO ռոք խումբը առաջին անգամ Երևանում Way Down We Go և No Good հիթերով։	KALEO Երևանում
80425dbe-07b0-4bc9-9692-d01f4840fcc4	Валерий Меладзе	Большой сольный концерт Валерия Меладзе — все главные хиты за тридцать лет.	Concert	2026-08-12 03:00:00+07	#2A1A4A	https://upload.wikimedia.org/wikipedia/commons/e/e1/Valeriy_Meladze_photoshooting_at_Laima_Rendez_Vous_Jurmala_2017.jpg	4a6a2585-77a7-452b-9176-6dcd00a120ec	f	2026-07-02 22:06:01.387255+07	Վալերի Մելադզեի մեծ միակողմանի համերգը՝ երեսուն տարվա բոլոր հիթերը։	Վալերի Մելադզե
8f613878-6ce5-4960-8b0c-6bb7c2b93c70	Новогодний гала-концерт	Большой праздничный гала-концерт под Новый год — звёзды армянской и мировой сцены.	Festival	2026-12-30 02:00:00+07	#6B1F3A	https://upload.wikimedia.org/wikipedia/commons/thumb/b/b4/New_Year%27s_Eve_fireworks.jpg/1280px-New_Year%27s_Eve_fireworks.jpg	4a6a2585-77a7-452b-9176-6dcd00a120ec	t	2026-07-02 22:06:01.413072+07	Մեծ տոնական գալա համերգ Նոր տարվա առթիվ՝ հայ և համաշխարհային բեմի աստղերով։	Նորոգանյա գալա համերգ
1d531324-806a-41fe-ae96-7acea1f2e993	Иван Дорн	Концерт украинского певца и продюсера Ивана Дорна с программой лучших хитов.	Concert	2026-08-07 04:00:00+07	#FF6B9D	https://upload.wikimedia.org/wikipedia/commons/thumb/4/4c/Ivan_Dorn_2017.jpg/1280px-Ivan_Dorn_2017.jpg	3516ca9a-6893-4f9b-9d11-d2f8192770e7	t	2026-07-02 22:06:01.415887+07	Ուկրաինացի երգչի և պրոդյուսերի Իվան Դորնի համերգը լավագույն հիթերի ծրագրով։	Իվան Դորն
20e5c793-a2ff-4f5b-907a-cdc55b2b310d	Ромео и Джульетта	Бессмертная трагедия Шекспира в современной постановке Национального театра.	Theatre	2026-07-15 02:00:00+07	#8B1538	https://upload.wikimedia.org/wikipedia/commons/thumb/5/5f/Romeo_and_Juliet_tomb.jpg/1280px-Romeo_and_Juliet_tomb.jpg	4ce0f111-56ba-4de5-ac4b-563c9ba48dd6	f	2026-07-02 22:06:01.418343+07	Շեքսպիրի անմահ ողբերգությունը Ազգային թատրոնի ժամանակակից բեմադրությամբ։	Ռոմեո և Ջուլիետա
dbcca2b4-e0e8-4fc2-a486-0be33c473476	Dua Lipa World Tour	Мировая поп-звезда Dua Lipa впервые в Ереване! Грандиозное шоу с хитами Levitating, Don't Start Now.	Concert	2026-08-22 03:00:00+07	#EF4444	https://upload.wikimedia.org/wikipedia/commons/thumb/7/7e/Dua_Lipa_in_2018.jpg/1280px-Dua_Lipa_in_2018.jpg	4a6a2585-77a7-452b-9176-6dcd00a120ec	t	2026-07-02 22:06:01.420169+07	Համաշխարհային փոփ աստղ Dua Lipa-ն առաջին անգամ Երևանում։ Վեհափառ շոու Levitating, Don't Start Now հիթերով։	Dua Lipa World Tour
57a358ae-12c2-49b6-afab-67eec5f1d991	Stand-Up: Александр Незлобин	Большой сольный концерт популярного стендап-комика Александра Незлобина.	Theatre	2026-07-25 03:00:00+07	#F59E0B	https://upload.wikimedia.org/wikipedia/commons/thumb/9/91/Stand-up_comedy_microphone.jpg/1280px-Stand-up_comedy_microphone.jpg	3516ca9a-6893-4f9b-9d11-d2f8192770e7	f	2026-07-02 22:06:01.42187+07	Հայտնի սթենդափ կոմիկոս Ալեքսանդր Նեզլոբինի մեծ միակողմանի համերգը։	Stand-Up: Ալեքսանդր Նեզլոբին
1e0f5f45-a574-4515-bfc0-bb3bc5c73006	Jazz Night: Tigran Hamasyan	Всемирно известный армянский джазовый пианист Тигран Амасян с новой программой.	Concert	2026-07-31 03:00:00+07	#1E3A8A	https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Tigran_Hamasyan.jpg/1280px-Tigran_Hamasyan.jpg	4ce0f111-56ba-4de5-ac4b-563c9ba48dd6	t	2026-07-02 22:06:01.423653+07	Համաշխարհային հռչակ ունեցող հայ ջազ դաշնակահար Տիգրան Համասյանը նոր ծրագրով։	Jazz Night: Տիգրան Համասյան
63bf20d5-8e21-4728-a38d-118ae7b15f0e	Yerevan Street Food Festival	Крупнейший гастрономический фестиваль Еревана: уличная еда, мастер-классы, музыка.	Festival	2026-07-10 19:00:00+07	#DC2626	https://upload.wikimedia.org/wikipedia/commons/thumb/6/6d/Street_food_market.jpg/1280px-Street_food_market.jpg	1e99bfde-3c55-4072-9068-9cd741d94168	f	2026-07-02 22:06:01.425994+07	Երևանի խոշորագույն գաստրոնոմիական փառատոնը՝ փողոցային կերակուր, վարպետաց դասեր, երաժշտություն։	Երևանի փողոցային կերակրի փառատոն
5b6fafc7-21a5-4531-bf2b-994e692eb35e	Blockchain & AI Summit 2026	Международная конференция по блокчейну и искусственному интеллекту. Топовые спикеры из США, Европы и Азии.	Conference	2026-08-16 16:00:00+07	#8B5CF6	https://upload.wikimedia.org/wikipedia/commons/thumb/4/46/Bitcoin.svg/1280px-Bitcoin.svg.png	f363fa2a-71d6-444a-a7e5-d28a33cc50ff	f	2026-07-02 22:06:01.427763+07	Բլոկչեյնի և արհեստական ​​բանականության միջազգային կոնֆերանս։ Լավագույն բանախոսներ ԱՄՆ-ից, Եվրոպայից և Ասիայից։	Blockchain & AI Summit 2026
ce8d13b8-4f7b-4c3c-a1cc-7fec1ecfb439	Щелкунчик	Рождественская классика — балет Чайковского «Щелкунчик» в исполнении Национального балета.	Theatre	2026-12-15 01:00:00+07	#047857	https://upload.wikimedia.org/wikipedia/commons/thumb/1/19/Nutcracker_ballet.jpg/1280px-Nutcracker_ballet.jpg	4ce0f111-56ba-4de5-ac4b-563c9ba48dd6	t	2026-07-02 22:06:01.450983+07	Սուրբ Ծննդյան դասական բալետ՝ Չայկովսկու «Ընկուզկոտրիչը» Ազգային բալետի կատարմամբ։	Ընկուզկոտրիչը
1aa217aa-c25f-4a11-8ac2-c0281aee21da	Red Hot Chili Peppers	Легендарная рок-группа Red Hot Chili Peppers в Ереване! Хиты Californication, Under the Bridge и новый альбом.	Concert	2026-09-01 03:00:00+07	#DC2626	https://upload.wikimedia.org/wikipedia/commons/thumb/c/c6/Red_Hot_Chili_Peppers_2016.jpg/1280px-Red_Hot_Chili_Peppers_2016.jpg	4a6a2585-77a7-452b-9176-6dcd00a120ec	t	2026-07-02 22:06:01.453378+07	Լեգենդար Red Hot Chili Peppers ռոք խումբը Երևանում։ Californication, Under the Bridge հիթերը և նոր ալբոմը։	Red Hot Chili Peppers
b29f667a-21dc-4475-9a81-ea8f6d56ead0	Фотовыставка «Армения сквозь века»	Уникальная выставка исторических и современных фотографий Армении от ведущих фотохудожников.	Exhibition	2026-07-07 17:00:00+07	#6366F1	https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/Photography_exhibition.jpg/1280px-Photography_exhibition.jpg	f363fa2a-71d6-444a-a7e5-d28a33cc50ff	f	2026-07-02 22:06:01.455284+07	Հայաստանի պատմական և ժամանակակից լուսանկարների եզակի ցուցահանդես առաջատար լուսանկարիչների կողմից։	Լուսանկարչական ցուցահանդես «Հայաստանը դարերի միջով»
8e5943fa-cd6e-4ca2-9247-f42bb6847dd8	Halloween Horror Night	Грандиозная хэллоуинская вечеринка с лучшими диджеями Армении, костюмированное шоу и призы.	Festival	2026-10-31 04:00:00+07	#FB923C	https://upload.wikimedia.org/wikipedia/commons/thumb/5/57/Halloween_pumpkins.jpg/1280px-Halloween_pumpkins.jpg	3516ca9a-6893-4f9b-9d11-d2f8192770e7	t	2026-07-02 22:06:01.456734+07	Վեհափառ Halloween երեկույթ Հայաստանի լավագույն DJ-ների, կոստյումների շոուի և մրցանակների հետ։	Halloween Horror Night
\.


--
-- Data for Name: Orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Orders" ("Id", "UserId", "Total", "Currency", "Status", "CreatedAt", "PaidAt") FROM stdin;
a9e4c914-2602-4685-bee6-91d87bcad764	38f2cd0b-fd45-4f42-a768-0ef45a3765df	6000.00	AMD	Paid	2026-07-02 22:21:12.835322+07	2026-07-02 22:21:12.845511+07
66ef6455-1389-4d62-ae88-403d9d626d82	d85b1613-5ac4-41c4-b304-7661dba93b35	3000.00	AMD	Paid	2026-07-02 22:21:37.344477+07	2026-07-02 22:21:37.345661+07
\.


--
-- Data for Name: SeatBlocks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."SeatBlocks" ("Id", "VenueFloorId", "SeatType", "DefaultPrice", "DefaultDescription", "DefaultColor", "CanvasX", "CanvasY", "RotationDeg", "Rows", "SeatsPerRow") FROM stdin;
522c7664-d846-4afb-b31e-b1662768a82c	5f04cea6-db8e-428f-8f94-4b7f621d770b	VIP	15000.00	VIP с обслуживанием	#FFD700	0	0	0	2	3
\.


--
-- Data for Name: SeatReservations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."SeatReservations" ("Id", "EventId", "SessionId", "EventSeatId", "ReservedAt", "ExpiresAt") FROM stdin;
\.


--
-- Data for Name: Seats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Seats" ("Id", "SeatBlockId", "Row", "Number", "SeatType", "Price", "Description", "Color", "CanvasX", "CanvasY", "IsActive") FROM stdin;
1648ee33-bec9-4cb8-8391-673250e886eb	522c7664-d846-4afb-b31e-b1662768a82c	1	2	VIP	15000.00	\N	#FFD700	0	-23	t
39f0e4d4-8d05-4bcb-bb41-874eab071620	522c7664-d846-4afb-b31e-b1662768a82c	2	4	VIP	15000.00	\N	#FFD700	-46	23	t
3d4c7423-00d4-4c97-b754-b68412c6998e	522c7664-d846-4afb-b31e-b1662768a82c	2	6	VIP	15000.00	\N	#FFD700	46	23	t
d526ff3d-9703-4b91-a8b7-0842471555a7	522c7664-d846-4afb-b31e-b1662768a82c	1	1	VIP	15000.00	\N	#FFD700	-46	-23	t
f6c7ed09-b0d2-41d3-8f0f-2188ce0deaa3	522c7664-d846-4afb-b31e-b1662768a82c	1	3	VIP	15000.00	\N	#FFD700	46	-23	t
fb006af0-405e-42cb-ad41-a65c882f680f	522c7664-d846-4afb-b31e-b1662768a82c	2	5	VIP	15000.00	\N	#FFD700	0	23	t
\.


--
-- Data for Name: Stages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Stages" ("Id", "VenueFloorId", "CanvasX", "CanvasY", "Width", "Height", "Label") FROM stdin;
35a17758-3aae-44e9-b867-ac873f0a5282	5f04cea6-db8e-428f-8f94-4b7f621d770b	0	-200	240	64	СЦЕНА
\.


--
-- Data for Name: TicketTypes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."TicketTypes" ("Id", "Name", "Price", "Currency", "Quantity", "Sold", "EventId", "NameAm") FROM stdin;
4b26aaa0-e8e5-4e7e-ab70-8e17823cc9f6	VIP	60000.00	AMD	500	0	a0b6368e-822d-4fd5-bea5-becff7ae080b	VIP
dff11d64-33a3-4440-962c-ef80bccc51d0	Трибуна	25000.00	AMD	8000	0	a0b6368e-822d-4fd5-bea5-becff7ae080b	Տրիբունա
ec9f3d84-a16f-4a1c-abbb-e73432ac7ac5	Фан-зона	15000.00	AMD	5000	0	a0b6368e-822d-4fd5-bea5-becff7ae080b	Ֆան-զոնա
7489da8a-cc0a-482f-9113-be7b67028920	Партер	12000.00	AMD	300	0	009b0bb3-7b2e-44f9-a708-aebbc32c734f	Պարտեր
b5e55898-2a15-4bb4-99bb-2856011b1740	Балкон	6000.00	AMD	200	0	009b0bb3-7b2e-44f9-a708-aebbc32c734f	Պատշգամբ
1328d7b8-da76-4f69-8e89-0d2740381c21	Вход	3000.00	AMD	10000	0	8e37eff8-3f80-4182-bd73-586b861e3919	Մուտք
736e671f-2083-4522-bee1-232a0ca07230	Pro	45000.00	AMD	200	0	b2a87ebc-b5d9-4938-86bf-cfc1ddd7bfae	Pro
ce2935f5-2268-4728-86a0-ab69fbc35be0	Standard	20000.00	AMD	800	0	b2a87ebc-b5d9-4938-86bf-cfc1ddd7bfae	Standard
0ddda875-d659-4929-a557-6ebeefb952e0	Категория A	15000.00	AMD	300	0	563e8692-6b49-4c03-b47b-4d038280f165	Կատեգորիա A
a5b66eb5-2988-4383-8468-bc54414d6d7b	Категория B	8000.00	AMD	400	0	563e8692-6b49-4c03-b47b-4d038280f165	Կատեգորիա B
32a2e680-a0cd-4b2e-88f1-2d0b5ba2bd87	Билет	4000.00	AMD	2000	0	2b570bea-d33c-44d7-967a-85a75bfe5802	Տոմս
49cefeaa-eee3-4552-a9dd-4807abcafe84	Танцпол	14000.00	AMD	1500	0	7a137412-0e28-4678-8e9e-62d7c82ad3f1	Պարահրապարակ
7f4280c3-6769-4019-825b-e3962ab50d54	Фан-зона	8000.00	AMD	3000	0	7a137412-0e28-4678-8e9e-62d7c82ad3f1	Ֆան-զոնա
fa942d20-f58f-4122-b1f4-e7b3c3f3471a	VIP	28000.00	AMD	200	0	7a137412-0e28-4678-8e9e-62d7c82ad3f1	VIP
52067994-c3cf-4ee9-8b1e-2beefd3c5a5e	Балкон	12000.00	AMD	1000	0	80425dbe-07b0-4bc9-9692-d01f4840fcc4	Պատշգամբ
6233b070-94f9-4ee3-8844-01e4c19d6764	Партер	22000.00	AMD	2000	0	80425dbe-07b0-4bc9-9692-d01f4840fcc4	Պարտեր
abe66d24-93a3-4a51-9f2b-49b28bbe1bf4	VIP	45000.00	AMD	300	0	80425dbe-07b0-4bc9-9692-d01f4840fcc4	VIP
33331ccf-a8f7-4a5a-8580-ed88f45c7f87	VIP	30000.00	AMD	500	0	8f613878-6ce5-4960-8b0c-6bb7c2b93c70	VIP
363278f8-021b-4353-947b-cc4aee93ca68	Стандарт	10000.00	AMD	5000	0	8f613878-6ce5-4960-8b0c-6bb7c2b93c70	Ստանդարտ
3e66d601-1aba-49dc-8455-844a1756c7c8	VIP	25000.00	AMD	300	0	1d531324-806a-41fe-ae96-7acea1f2e993	VIP
5397e9d7-c03d-41e4-a85d-6ae6b1748aa2	Партер	12000.00	AMD	1800	0	1d531324-806a-41fe-ae96-7acea1f2e993	Պարտեր
647a9909-f407-4e47-afaa-9208cb9a13fd	Фан-зона	7000.00	AMD	2500	0	1d531324-806a-41fe-ae96-7acea1f2e993	Ֆան-զոնա
0f275764-82a3-451a-a295-7a281f647c58	Ложа	18000.00	AMD	50	0	20e5c793-a2ff-4f5b-907a-cdc55b2b310d	Ապարանք
8df4bc34-151f-4eda-921a-aab3d12dac05	Балкон	5000.00	AMD	250	0	20e5c793-a2ff-4f5b-907a-cdc55b2b310d	Պատշգամբ
cfbfc6e6-079e-4d59-bf6d-64715b63e775	Партер	9000.00	AMD	350	0	20e5c793-a2ff-4f5b-907a-cdc55b2b310d	Պարտեր
08fa67e4-ae04-4c2d-940a-8c5cec1a938a	Фан-зона	18000.00	AMD	6000	0	dbcca2b4-e0e8-4fc2-a486-0be33c473476	Ֆան-զոնա
34774e19-ec0e-42a3-9b5e-cab33ff09ee1	Трибуна	30000.00	AMD	10000	0	dbcca2b4-e0e8-4fc2-a486-0be33c473476	Տրիբունա
b336f644-ec2e-4060-9c2b-80fea282aeac	VIP	85000.00	AMD	400	0	dbcca2b4-e0e8-4fc2-a486-0be33c473476	VIP
ed12fa46-7cd1-42d2-b13b-090ed0679e90	Golden Circle	50000.00	AMD	800	0	dbcca2b4-e0e8-4fc2-a486-0be33c473476	Golden Circle
1d7045be-a626-4667-bf4b-28f3c10d3b6a	Партер	8000.00	AMD	1200	0	57a358ae-12c2-49b6-afab-67eec5f1d991	Պարտեր
5e72f82f-4f25-44ec-a780-dd3149952958	VIP	15000.00	AMD	400	0	57a358ae-12c2-49b6-afab-67eec5f1d991	VIP
2c0af98a-fde1-4f9d-acab-70cd5346d9de	VIP	35000.00	AMD	100	0	1e0f5f45-a574-4515-bfc0-bb3bc5c73006	VIP
2e344374-0b14-4ce8-b073-7c327cb91b9d	Балкон	10000.00	AMD	300	0	1e0f5f45-a574-4515-bfc0-bb3bc5c73006	Պատշգամբ
56ee7f3f-222b-4152-bb37-659d9fb829e0	Партер	18000.00	AMD	400	0	1e0f5f45-a574-4515-bfc0-bb3bc5c73006	Պարտեր
f72081ce-a242-4ce7-b625-71892d84e811	Входной билет	2000.00	AMD	15000	0	63bf20d5-8e21-4728-a38d-118ae7b15f0e	Մուտքի տոմս
0428b0aa-bc1b-414e-bda4-c9e0ae4bdc83	Standard	25000.00	AMD	1000	0	5b6fafc7-21a5-4531-bf2b-994e692eb35e	Standard
7a1b3796-fb49-4090-9fd7-9f20b7e617d2	Early Bird	15000.00	AMD	500	0	5b6fafc7-21a5-4531-bf2b-994e692eb35e	Early Bird
9120b1b5-1464-4974-b207-b118bab295f5	VIP + Networking	60000.00	AMD	150	0	5b6fafc7-21a5-4531-bf2b-994e692eb35e	VIP + Networking
463b3e06-603e-4ed6-953e-ee32a119ccec	Партер	14000.00	AMD	350	0	ce8d13b8-4f7b-4c3c-a1cc-7fec1ecfb439	Պարտեր
7923eaec-9fa2-43ad-be34-52b6fb25da3f	Балкон	7000.00	AMD	250	0	ce8d13b8-4f7b-4c3c-a1cc-7fec1ecfb439	Պատշգամբ
d39bca3e-88c5-4549-a2fb-8c840fa8b087	VIP	28000.00	AMD	100	0	ce8d13b8-4f7b-4c3c-a1cc-7fec1ecfb439	VIP
13e7c10a-ac43-4ed1-94bf-fe5bf2fbaea1	Трибуна	35000.00	AMD	12000	0	1aa217aa-c25f-4a11-8ac2-c0281aee21da	Տրիբունա
8a09e701-44a0-444d-9806-e9b3a3b0deb6	Фан-зона	20000.00	AMD	8000	0	1aa217aa-c25f-4a11-8ac2-c0281aee21da	Ֆան-զոնա
b5515387-a4ab-42be-8988-ed1cec07f87f	VIP	95000.00	AMD	500	0	1aa217aa-c25f-4a11-8ac2-c0281aee21da	VIP
c42f1393-bcfd-45f0-bc10-333890dae67d	Golden Circle	60000.00	AMD	1000	0	1aa217aa-c25f-4a11-8ac2-c0281aee21da	Golden Circle
842af2f5-b472-48dd-a6d5-60aaf4eb5b90	Обычный	6000.00	AMD	2000	0	8e5943fa-cd6e-4ca2-9247-f42bb6847dd8	Սովորական
9a1cf87f-766d-4a3a-8cc5-f59521c9b5ba	VIP + бар	15000.00	AMD	500	0	8e5943fa-cd6e-4ca2-9247-f42bb6847dd8	VIP + բար
374b8953-8b58-44c7-9ff3-0b8ac0a23953	Билет	3000.00	AMD	3000	3	b29f667a-21dc-4475-9a81-ea8f6d56ead0	Տոմս
\.


--
-- Data for Name: Tickets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Tickets" ("Id", "OrderId", "TicketTypeId", "EventId", "QrToken", "Status", "IssuedAt", "CheckedInAt", "TransferredTo", "TransferredAt", "AppUserId", "EventSeatId", "Price", "TypeName") FROM stdin;
1437c2bb-474a-41f9-8521-6c1adec9fe48	a9e4c914-2602-4685-bee6-91d87bcad764	374b8953-8b58-44c7-9ff3-0b8ac0a23953	b29f667a-21dc-4475-9a81-ea8f6d56ead0	419d20599a744cc8a7ea7f6708e1e16a	Issued	2026-07-02 22:21:12.845458+07	\N	\N	\N	\N	\N	3000.00	Билет
aa61647c-7503-4771-846e-920ef9dd4abe	a9e4c914-2602-4685-bee6-91d87bcad764	374b8953-8b58-44c7-9ff3-0b8ac0a23953	b29f667a-21dc-4475-9a81-ea8f6d56ead0	3da0e6e5761748d2a9c5f7b28213d255	Issued	2026-07-02 22:21:12.845295+07	\N	\N	\N	\N	\N	3000.00	Билет
8781cfc5-3765-4539-92de-5bf53e0104d4	66ef6455-1389-4d62-ae88-403d9d626d82	374b8953-8b58-44c7-9ff3-0b8ac0a23953	b29f667a-21dc-4475-9a81-ea8f6d56ead0	e851f4f9075549a89823dab909db47cd	Transferred	2026-07-02 22:21:37.345658+07	\N	89832092297	2026-07-02 22:21:47.34609+07	\N	\N	3000.00	Билет
\.


--
-- Data for Name: Users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Users" ("Id", "DisplayName", "Phone", "City", "CreatedAt", "OtpCode", "OtpExpiresAt", "SessionToken", "Email", "IsAdmin") FROM stdin;
c1fd42c3-f910-4ef9-b2f0-c947180a21a4	Test	+37477000111	Yerevan	2026-07-02 22:06:52.48754+07	0000	2026-07-02 22:11:52.514398+07	\N	\N	f
d85b1613-5ac4-41c4-b304-7661dba93b35	Гость	89832092298	Yerevan	2026-07-02 22:21:27.83188+07	\N	\N	6500e3564f954c88ae65d6cb75eebd50f1746b99a65a44118d136f18833d94bb	\N	f
38f2cd0b-fd45-4f42-a768-0ef45a3765df	Гость	89832092297	Yerevan	2026-07-02 22:19:54.281683+07	\N	\N	5ffef0c2d2ae4010af02d0e46b5f609bee64dc3f44f74d23b2c048fd8139029f	\N	f
\.


--
-- Data for Name: VenueFloors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."VenueFloors" ("Id", "VenueLayoutId", "Name", "Order") FROM stdin;
5f04cea6-db8e-428f-8f94-4b7f621d770b	5cace409-e210-4ba8-9cc1-f0e35140aaf4	Партер	0
\.


--
-- Data for Name: VenueLayouts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."VenueLayouts" ("Id", "VenueId", "Name", "CreatedAt") FROM stdin;
5cace409-e210-4ba8-9cc1-f0e35140aaf4	f363fa2a-71d6-444a-a7e5-d28a33cc50ff	Главный зал	2026-07-02 22:07:18.985038+07
\.


--
-- Data for Name: Venues; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."Venues" ("Id", "Name", "City", "Address", "Latitude", "Longitude", "AddressAm", "NameAm") FROM stdin;
1e99bfde-3c55-4072-9068-9cd741d94168	Улица Сарьяна	Yerevan	ул. Сарьяна	40.184	44.5095	Սարյան փողոց	Սարյան փողոց
3516ca9a-6893-4f9b-9d11-d2f8192770e7	Концертный зал им. Демирчяна	Yerevan	ул. Цицернакаберди 1	40.1772	44.4862	Ծիծեռնակաբերդի փողոց 1	Դեմիրճյանի անվան համերգասրահ
4a6a2585-77a7-452b-9176-6dcd00a120ec	Республиканский стадион	Yerevan	ул. Цицернакаберди	40.1745	44.4894	Ծիծեռնակաբերդի փողոց	Հանրապետական ստադիոն
4ce0f111-56ba-4de5-ac4b-563c9ba48dd6	Театр оперы и балета	Yerevan	пл. Свободы 54	40.1869	44.5147	Ազատության հրապարակ 54	Օպերայի և բալետի թատրոն
f363fa2a-71d6-444a-a7e5-d28a33cc50ff	Meridian Expo Center	Yerevan	ул. Дзорап 50	40.1577	44.4978	Ձորափի փողոց 50	Meridian Expo Center
\.


--
-- Data for Name: __EFMigrationsHistory; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."__EFMigrationsHistory" ("MigrationId", "ProductVersion") FROM stdin;
20260630081251_AddAuthFieldsToAppUser	8.0.6
20260630091230_AddMultilingualFields	8.0.6
20260630103723_AddUserEmailAndIsAdmin	8.0.6
20260702145548_AddSeatingPlan	8.0.6
\.


--
-- Name: EventFloors PK_EventFloors; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventFloors"
    ADD CONSTRAINT "PK_EventFloors" PRIMARY KEY ("Id");


--
-- Name: EventLayouts PK_EventLayouts; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventLayouts"
    ADD CONSTRAINT "PK_EventLayouts" PRIMARY KEY ("Id");


--
-- Name: EventSeatBlocks PK_EventSeatBlocks; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventSeatBlocks"
    ADD CONSTRAINT "PK_EventSeatBlocks" PRIMARY KEY ("Id");


--
-- Name: EventSeats PK_EventSeats; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventSeats"
    ADD CONSTRAINT "PK_EventSeats" PRIMARY KEY ("Id");


--
-- Name: EventStages PK_EventStages; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventStages"
    ADD CONSTRAINT "PK_EventStages" PRIMARY KEY ("Id");


--
-- Name: Events PK_Events; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Events"
    ADD CONSTRAINT "PK_Events" PRIMARY KEY ("Id");


--
-- Name: Orders PK_Orders; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Orders"
    ADD CONSTRAINT "PK_Orders" PRIMARY KEY ("Id");


--
-- Name: SeatBlocks PK_SeatBlocks; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."SeatBlocks"
    ADD CONSTRAINT "PK_SeatBlocks" PRIMARY KEY ("Id");


--
-- Name: SeatReservations PK_SeatReservations; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."SeatReservations"
    ADD CONSTRAINT "PK_SeatReservations" PRIMARY KEY ("Id");


--
-- Name: Seats PK_Seats; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Seats"
    ADD CONSTRAINT "PK_Seats" PRIMARY KEY ("Id");


--
-- Name: Stages PK_Stages; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Stages"
    ADD CONSTRAINT "PK_Stages" PRIMARY KEY ("Id");


--
-- Name: TicketTypes PK_TicketTypes; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."TicketTypes"
    ADD CONSTRAINT "PK_TicketTypes" PRIMARY KEY ("Id");


--
-- Name: Tickets PK_Tickets; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tickets"
    ADD CONSTRAINT "PK_Tickets" PRIMARY KEY ("Id");


--
-- Name: Users PK_Users; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "PK_Users" PRIMARY KEY ("Id");


--
-- Name: VenueFloors PK_VenueFloors; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."VenueFloors"
    ADD CONSTRAINT "PK_VenueFloors" PRIMARY KEY ("Id");


--
-- Name: VenueLayouts PK_VenueLayouts; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."VenueLayouts"
    ADD CONSTRAINT "PK_VenueLayouts" PRIMARY KEY ("Id");


--
-- Name: Venues PK_Venues; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Venues"
    ADD CONSTRAINT "PK_Venues" PRIMARY KEY ("Id");


--
-- Name: __EFMigrationsHistory PK___EFMigrationsHistory; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."__EFMigrationsHistory"
    ADD CONSTRAINT "PK___EFMigrationsHistory" PRIMARY KEY ("MigrationId");


--
-- Name: IX_EventFloors_EventLayoutId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_EventFloors_EventLayoutId" ON public."EventFloors" USING btree ("EventLayoutId");


--
-- Name: IX_EventLayouts_EventId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "IX_EventLayouts_EventId" ON public."EventLayouts" USING btree ("EventId");


--
-- Name: IX_EventSeatBlocks_EventFloorId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_EventSeatBlocks_EventFloorId" ON public."EventSeatBlocks" USING btree ("EventFloorId");


--
-- Name: IX_EventSeats_EventSeatBlockId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_EventSeats_EventSeatBlockId" ON public."EventSeats" USING btree ("EventSeatBlockId");


--
-- Name: IX_EventStages_EventFloorId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "IX_EventStages_EventFloorId" ON public."EventStages" USING btree ("EventFloorId");


--
-- Name: IX_Events_VenueId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_Events_VenueId" ON public."Events" USING btree ("VenueId");


--
-- Name: IX_Orders_UserId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_Orders_UserId" ON public."Orders" USING btree ("UserId");


--
-- Name: IX_SeatBlocks_VenueFloorId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_SeatBlocks_VenueFloorId" ON public."SeatBlocks" USING btree ("VenueFloorId");


--
-- Name: IX_SeatReservations_EventId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_SeatReservations_EventId" ON public."SeatReservations" USING btree ("EventId");


--
-- Name: IX_SeatReservations_EventSeatId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_SeatReservations_EventSeatId" ON public."SeatReservations" USING btree ("EventSeatId");


--
-- Name: IX_SeatReservations_ExpiresAt; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_SeatReservations_ExpiresAt" ON public."SeatReservations" USING btree ("ExpiresAt");


--
-- Name: IX_SeatReservations_SessionId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_SeatReservations_SessionId" ON public."SeatReservations" USING btree ("SessionId");


--
-- Name: IX_Seats_SeatBlockId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_Seats_SeatBlockId" ON public."Seats" USING btree ("SeatBlockId");


--
-- Name: IX_Stages_VenueFloorId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "IX_Stages_VenueFloorId" ON public."Stages" USING btree ("VenueFloorId");


--
-- Name: IX_TicketTypes_EventId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_TicketTypes_EventId" ON public."TicketTypes" USING btree ("EventId");


--
-- Name: IX_Tickets_AppUserId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_Tickets_AppUserId" ON public."Tickets" USING btree ("AppUserId");


--
-- Name: IX_Tickets_EventId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_Tickets_EventId" ON public."Tickets" USING btree ("EventId");


--
-- Name: IX_Tickets_EventSeatId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_Tickets_EventSeatId" ON public."Tickets" USING btree ("EventSeatId");


--
-- Name: IX_Tickets_OrderId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_Tickets_OrderId" ON public."Tickets" USING btree ("OrderId");


--
-- Name: IX_Tickets_QrToken; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "IX_Tickets_QrToken" ON public."Tickets" USING btree ("QrToken");


--
-- Name: IX_Tickets_TicketTypeId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_Tickets_TicketTypeId" ON public."Tickets" USING btree ("TicketTypeId");


--
-- Name: IX_VenueFloors_VenueLayoutId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_VenueFloors_VenueLayoutId" ON public."VenueFloors" USING btree ("VenueLayoutId");


--
-- Name: IX_VenueLayouts_Name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_VenueLayouts_Name" ON public."VenueLayouts" USING btree ("Name");


--
-- Name: IX_VenueLayouts_VenueId; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "IX_VenueLayouts_VenueId" ON public."VenueLayouts" USING btree ("VenueId");


--
-- Name: EventFloors FK_EventFloors_EventLayouts_EventLayoutId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventFloors"
    ADD CONSTRAINT "FK_EventFloors_EventLayouts_EventLayoutId" FOREIGN KEY ("EventLayoutId") REFERENCES public."EventLayouts"("Id") ON DELETE CASCADE;


--
-- Name: EventLayouts FK_EventLayouts_Events_EventId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventLayouts"
    ADD CONSTRAINT "FK_EventLayouts_Events_EventId" FOREIGN KEY ("EventId") REFERENCES public."Events"("Id") ON DELETE CASCADE;


--
-- Name: EventSeatBlocks FK_EventSeatBlocks_EventFloors_EventFloorId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventSeatBlocks"
    ADD CONSTRAINT "FK_EventSeatBlocks_EventFloors_EventFloorId" FOREIGN KEY ("EventFloorId") REFERENCES public."EventFloors"("Id") ON DELETE CASCADE;


--
-- Name: EventSeats FK_EventSeats_EventSeatBlocks_EventSeatBlockId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventSeats"
    ADD CONSTRAINT "FK_EventSeats_EventSeatBlocks_EventSeatBlockId" FOREIGN KEY ("EventSeatBlockId") REFERENCES public."EventSeatBlocks"("Id") ON DELETE CASCADE;


--
-- Name: EventStages FK_EventStages_EventFloors_EventFloorId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."EventStages"
    ADD CONSTRAINT "FK_EventStages_EventFloors_EventFloorId" FOREIGN KEY ("EventFloorId") REFERENCES public."EventFloors"("Id") ON DELETE CASCADE;


--
-- Name: Events FK_Events_Venues_VenueId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Events"
    ADD CONSTRAINT "FK_Events_Venues_VenueId" FOREIGN KEY ("VenueId") REFERENCES public."Venues"("Id") ON DELETE RESTRICT;


--
-- Name: Orders FK_Orders_Users_UserId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Orders"
    ADD CONSTRAINT "FK_Orders_Users_UserId" FOREIGN KEY ("UserId") REFERENCES public."Users"("Id") ON DELETE CASCADE;


--
-- Name: SeatBlocks FK_SeatBlocks_VenueFloors_VenueFloorId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."SeatBlocks"
    ADD CONSTRAINT "FK_SeatBlocks_VenueFloors_VenueFloorId" FOREIGN KEY ("VenueFloorId") REFERENCES public."VenueFloors"("Id") ON DELETE CASCADE;


--
-- Name: Seats FK_Seats_SeatBlocks_SeatBlockId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Seats"
    ADD CONSTRAINT "FK_Seats_SeatBlocks_SeatBlockId" FOREIGN KEY ("SeatBlockId") REFERENCES public."SeatBlocks"("Id") ON DELETE CASCADE;


--
-- Name: Stages FK_Stages_VenueFloors_VenueFloorId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Stages"
    ADD CONSTRAINT "FK_Stages_VenueFloors_VenueFloorId" FOREIGN KEY ("VenueFloorId") REFERENCES public."VenueFloors"("Id") ON DELETE CASCADE;


--
-- Name: TicketTypes FK_TicketTypes_Events_EventId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."TicketTypes"
    ADD CONSTRAINT "FK_TicketTypes_Events_EventId" FOREIGN KEY ("EventId") REFERENCES public."Events"("Id") ON DELETE CASCADE;


--
-- Name: Tickets FK_Tickets_EventSeats_EventSeatId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tickets"
    ADD CONSTRAINT "FK_Tickets_EventSeats_EventSeatId" FOREIGN KEY ("EventSeatId") REFERENCES public."EventSeats"("Id") ON DELETE RESTRICT;


--
-- Name: Tickets FK_Tickets_Events_EventId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tickets"
    ADD CONSTRAINT "FK_Tickets_Events_EventId" FOREIGN KEY ("EventId") REFERENCES public."Events"("Id") ON DELETE CASCADE;


--
-- Name: Tickets FK_Tickets_Orders_OrderId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tickets"
    ADD CONSTRAINT "FK_Tickets_Orders_OrderId" FOREIGN KEY ("OrderId") REFERENCES public."Orders"("Id") ON DELETE CASCADE;


--
-- Name: Tickets FK_Tickets_TicketTypes_TicketTypeId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tickets"
    ADD CONSTRAINT "FK_Tickets_TicketTypes_TicketTypeId" FOREIGN KEY ("TicketTypeId") REFERENCES public."TicketTypes"("Id") ON DELETE RESTRICT;


--
-- Name: Tickets FK_Tickets_Users_AppUserId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Tickets"
    ADD CONSTRAINT "FK_Tickets_Users_AppUserId" FOREIGN KEY ("AppUserId") REFERENCES public."Users"("Id");


--
-- Name: VenueFloors FK_VenueFloors_VenueLayouts_VenueLayoutId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."VenueFloors"
    ADD CONSTRAINT "FK_VenueFloors_VenueLayouts_VenueLayoutId" FOREIGN KEY ("VenueLayoutId") REFERENCES public."VenueLayouts"("Id") ON DELETE CASCADE;


--
-- Name: VenueLayouts FK_VenueLayouts_Venues_VenueId; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."VenueLayouts"
    ADD CONSTRAINT "FK_VenueLayouts_Venues_VenueId" FOREIGN KEY ("VenueId") REFERENCES public."Venues"("Id") ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict PzWoxAIzodGPCAkl3nzF9XrNgaue66xCa85QK57uEAzer26pwXVbkBitwxuMDvL

