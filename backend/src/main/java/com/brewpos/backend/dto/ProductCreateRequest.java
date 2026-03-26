package com.brewpos.backend.dto;

public class ProductCreateRequest {

    private String  name;
    private String  section;
    private Double  sellPrice;
    private String  imageUrl;
    private String  barcode;
    private Integer initialStock;
    private Integer buyPrice;
    private String  unit;
    private Integer reorderLevel;

    // ── Getters ──────────────────────────────────────────────

    public String  getName()         { return name; }
    public String  getSection()      { return section; }
    public Double  getSellPrice()    { return sellPrice; }
    public String  getImageUrl()     { return imageUrl; }
    public String  getBarcode()      { return barcode; }
    public Integer getInitialStock() { return initialStock; }
    public Integer getBuyPrice()     { return buyPrice; }
    public String  getUnit()         { return unit; }
    public Integer getReorderLevel() { return reorderLevel; }

    // ── Setters ──────────────────────────────────────────────

    public void setName(String name)                  { this.name = name; }
    public void setSection(String section)            { this.section = section; }
    public void setSellPrice(Double sellPrice)        { this.sellPrice = sellPrice; }
    public void setImageUrl(String imageUrl)          { this.imageUrl = imageUrl; }
    public void setBarcode(String barcode)            { this.barcode = barcode; }
    public void setInitialStock(Integer initialStock) { this.initialStock = initialStock; }
    public void setBuyPrice(Integer buyPrice)         { this.buyPrice = buyPrice; }
    public void setUnit(String unit)                  { this.unit = unit; }
    public void setReorderLevel(Integer reorderLevel) { this.reorderLevel = reorderLevel; }
}